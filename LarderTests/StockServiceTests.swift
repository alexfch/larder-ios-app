import XCTest
@testable import Larder

@MainActor
final class StockServiceTests: XCTestCase {
    var store: InMemoryCatalogStore!

    override func setUpWithError() throws {
        store = InMemoryCatalogStore()
    }

    private func makeItem(name: String = "Tinned Tomatoes") -> Item {
        let item = Item(name: name, packaging: .packaged, packageName: "tin")
        try? store.addItem(item)
        return item
    }

    private func onHandTotal(_ item: Item) -> Double {
        CatalogDerivation.onHandTotal(itemId: item.id, transactions: store.transactions)
    }

    private func lots(_ item: Item) -> [Lot] {
        CatalogDerivation.sortedLots(itemId: item.id, transactions: store.transactions)
    }

    func testCheckInCreatesNewLot() throws {
        let item = makeItem()
        let exp = Date(timeIntervalSince1970: 2_000_000_000)

        try StockService.checkIn(itemId: item.id, qty: 4, exp: exp, store: store)

        XCTAssertEqual(lots(item).count, 1)
        XCTAssertEqual(onHandTotal(item), 4)
        XCTAssertEqual(store.transactions(for: item.id).count, 1)
        XCTAssertEqual(store.transactions(for: item.id).first?.action, .checkIn)
    }

    func testCheckInMergesIntoExistingLotOnSameDate() throws {
        let item = makeItem()
        let exp = Date(timeIntervalSince1970: 2_000_000_000)

        try StockService.checkIn(itemId: item.id, qty: 4, exp: exp, store: store)
        try StockService.checkIn(itemId: item.id, qty: 3, exp: exp, store: store)

        XCTAssertEqual(lots(item).count, 1)
        XCTAssertEqual(onHandTotal(item), 7)
        XCTAssertEqual(store.transactions(for: item.id).count, 2)
    }

    func testCheckOutDrawsOldestLotFirst() throws {
        let item = makeItem()
        // checkIn normalizes exp to the start of its local day, so compare against the same
        // normalization rather than the raw timestamp.
        let older = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_000_000_000))
        let newer = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 2_000_000_000))

        try StockService.checkIn(itemId: item.id, qty: 5, exp: newer, store: store)
        try StockService.checkIn(itemId: item.id, qty: 3, exp: older, store: store)

        try StockService.checkOut(itemId: item.id, qty: 3, store: store)

        XCTAssertEqual(lots(item).count, 1)
        XCTAssertEqual(lots(item).first?.exp ?? nil, newer)
        XCTAssertEqual(onHandTotal(item), 5)
    }

    func testCheckOutCascadesAcrossMultipleLots() throws {
        let item = makeItem()
        let older = Date(timeIntervalSince1970: 1_000_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000_000)

        try StockService.checkIn(itemId: item.id, qty: 2, exp: older, store: store)
        try StockService.checkIn(itemId: item.id, qty: 5, exp: newer, store: store)

        let transactions = try StockService.checkOut(itemId: item.id, qty: 4, store: store)

        XCTAssertEqual(onHandTotal(item), 3)
        XCTAssertEqual(lots(item).count, 1)
        XCTAssertEqual(transactions.count, 2, "should split across the two lots it drew from")
    }

    func testCheckOutThrowsWhenInsufficientStock() throws {
        let item = makeItem()
        try StockService.checkIn(itemId: item.id, qty: 2, exp: .now, store: store)

        XCTAssertThrowsError(try StockService.checkOut(itemId: item.id, qty: 10, store: store)) { error in
            XCTAssertTrue(error is StockServiceError)
        }
        XCTAssertEqual(onHandTotal(item), 2, "a failed check-out must not partially mutate stock")
    }

    func testRemoveCheckOutRollsBackBalance() throws {
        let item = makeItem()
        try StockService.checkIn(itemId: item.id, qty: 10, exp: .now, store: store)
        let transactions = try StockService.checkOut(itemId: item.id, qty: 4, store: store)

        try StockService.remove(transactions[0], store: store)

        XCTAssertEqual(onHandTotal(item), 10)
    }

    func testRemoveCheckInRollsBackBalance() throws {
        let item = makeItem()
        let transaction = try StockService.checkIn(itemId: item.id, qty: 6, exp: .now, store: store)

        try StockService.remove(transaction, store: store)

        XCTAssertEqual(onHandTotal(item), 0)
        XCTAssertEqual(lots(item).count, 0)
    }

    func testRemoveThrowsAndLeavesTransactionIntactWhenReversalExceedsAvailableStock() throws {
        // Regression test: removing a check-in that can no longer be fully reversed (because
        // stock has since moved elsewhere) must throw before mutating anything, and the
        // transaction must remain in history.
        let item = makeItem()
        let checkIn = try StockService.checkIn(itemId: item.id, qty: 5, exp: .now, store: store)
        try StockService.checkOut(itemId: item.id, qty: 3, store: store)

        XCTAssertEqual(onHandTotal(item), 2)

        XCTAssertThrowsError(try StockService.remove(checkIn, store: store)) { error in
            XCTAssertTrue(error is StockServiceError)
        }

        XCTAssertEqual(onHandTotal(item), 2, "a failed remove must not partially reverse anything")
        XCTAssertTrue(store.transactions.contains { $0.id == checkIn.id }, "the transaction must remain if it couldn't be safely removed")
    }

    func testEditCheckInQuantityUpdatesBalance() throws {
        let item = makeItem()
        let exp = Date(timeIntervalSince1970: 2_000_000_000)
        let transaction = try StockService.checkIn(itemId: item.id, qty: 5, exp: exp, store: store)

        try StockService.edit(transaction, newQty: 9, newExp: exp, store: store)

        XCTAssertEqual(onHandTotal(item), 9)
        XCTAssertEqual(lots(item).count, 1)
    }

    func testEditThrowsAndLeavesBalanceUntouchedWhenNewQuantityExceedsAvailableStock() throws {
        // Regression test: editing a check-out up to a quantity the item can no longer cover must
        // fail before mutating anything, leaving both the balance and the original transaction
        // intact.
        let item = makeItem()
        try StockService.checkIn(itemId: item.id, qty: 10, exp: .now, store: store)
        let transactions = try StockService.checkOut(itemId: item.id, qty: 4, store: store)
        let checkOut = transactions[0]

        XCTAssertEqual(onHandTotal(item), 6)

        XCTAssertThrowsError(try StockService.edit(checkOut, newQty: 100, newExp: checkOut.exp, store: store)) { error in
            XCTAssertTrue(error is StockServiceError)
        }

        XCTAssertEqual(onHandTotal(item), 6, "a failed edit must not partially reverse or apply anything")
        XCTAssertEqual(store.transactions.first { $0.id == checkOut.id }?.qty, 4, "the original transaction must be untouched")
    }
}
