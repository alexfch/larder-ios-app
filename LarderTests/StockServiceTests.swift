import XCTest
import SwiftData
@testable import Larder

final class StockServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Item.self, Lot.self, Transaction.self, CountSession.self, CountLine.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    private func makeItem(name: String = "Tinned Tomatoes") -> Item {
        let item = Item(name: name, kind: .unit, noun: "tin")
        context.insert(item)
        return item
    }

    func testCheckInCreatesNewLot() {
        let item = makeItem()
        let exp = Date(timeIntervalSince1970: 2_000_000_000)

        StockService.checkIn(item: item, qty: 4, exp: exp, context: context)

        XCTAssertEqual(item.lots.count, 1)
        XCTAssertEqual(item.onHandTotal, 4)
        XCTAssertEqual(item.transactions.count, 1)
        XCTAssertEqual(item.transactions.first?.action, .checkIn)
    }

    func testCheckInMergesIntoExistingLotOnSameDate() {
        let item = makeItem()
        let exp = Date(timeIntervalSince1970: 2_000_000_000)

        StockService.checkIn(item: item, qty: 4, exp: exp, context: context)
        StockService.checkIn(item: item, qty: 3, exp: exp, context: context)

        XCTAssertEqual(item.lots.count, 1)
        XCTAssertEqual(item.onHandTotal, 7)
        XCTAssertEqual(item.transactions.count, 2)
    }

    func testCheckOutDrawsOldestLotFirst() throws {
        let item = makeItem()
        // checkIn normalizes exp to the start of its local day, so compare against the same
        // normalization rather than the raw timestamp.
        let older = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_000_000_000))
        let newer = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 2_000_000_000))

        StockService.checkIn(item: item, qty: 5, exp: newer, context: context)
        StockService.checkIn(item: item, qty: 3, exp: older, context: context)

        try StockService.checkOut(item: item, qty: 3, context: context)

        XCTAssertEqual(item.lots.count, 1)
        XCTAssertEqual(item.sortedLots.first?.exp, newer)
        XCTAssertEqual(item.onHandTotal, 5)
    }

    func testCheckOutCascadesAcrossMultipleLots() throws {
        let item = makeItem()
        let older = Date(timeIntervalSince1970: 1_000_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000_000)

        StockService.checkIn(item: item, qty: 2, exp: older, context: context)
        StockService.checkIn(item: item, qty: 5, exp: newer, context: context)

        let transactions = try StockService.checkOut(item: item, qty: 4, context: context)

        XCTAssertEqual(item.onHandTotal, 3)
        XCTAssertEqual(item.lots.count, 1)
        XCTAssertEqual(transactions.count, 2, "should split across the two lots it drew from")
    }

    func testCheckOutThrowsWhenInsufficientStock() {
        let item = makeItem()
        StockService.checkIn(item: item, qty: 2, exp: .now, context: context)

        XCTAssertThrowsError(try StockService.checkOut(item: item, qty: 10, context: context)) { error in
            XCTAssertTrue(error is StockServiceError)
        }
        XCTAssertEqual(item.onHandTotal, 2, "a failed check-out must not partially mutate stock")
    }

    func testRemoveCheckOutRollsBackBalance() throws {
        let item = makeItem()
        StockService.checkIn(item: item, qty: 10, exp: .now, context: context)
        let transactions = try StockService.checkOut(item: item, qty: 4, context: context)

        StockService.remove(transactions[0], context: context)

        XCTAssertEqual(item.onHandTotal, 10)
    }

    func testRemoveCheckInRollsBackBalance() {
        let item = makeItem()
        let transaction = StockService.checkIn(item: item, qty: 6, exp: .now, context: context)

        StockService.remove(transaction, context: context)

        XCTAssertEqual(item.onHandTotal, 0)
        XCTAssertEqual(item.lots.count, 0)
    }

    func testEditCheckInQuantityUpdatesBalanceAtomically() throws {
        let item = makeItem()
        let exp = Date(timeIntervalSince1970: 2_000_000_000)
        let transaction = StockService.checkIn(item: item, qty: 5, exp: exp, context: context)

        try StockService.edit(transaction, newQty: 9, newExp: exp, context: context)

        XCTAssertEqual(item.onHandTotal, 9)
        XCTAssertEqual(item.lots.count, 1)
    }
}
