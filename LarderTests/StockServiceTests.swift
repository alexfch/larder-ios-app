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

        try StockService.remove(transactions[0], context: context)

        XCTAssertEqual(item.onHandTotal, 10)
    }

    func testRemoveCheckInRollsBackBalance() throws {
        let item = makeItem()
        let transaction = StockService.checkIn(item: item, qty: 6, exp: .now, context: context)

        try StockService.remove(transaction, context: context)

        XCTAssertEqual(item.onHandTotal, 0)
        XCTAssertEqual(item.lots.count, 0)
    }

    func testRemoveThrowsAndLeavesTransactionIntactWhenReversalExceedsAvailableStock() throws {
        // Regression test for the validate-then-apply fix: reversing a check-in used to call
        // removeFromLots via a `try?` that silently swallowed failure, so a check-in could be
        // deleted from history while stock that had since moved elsewhere left its effect only
        // partially undone. Removing a check-in that can no longer be fully reversed must throw
        // before mutating anything, and the transaction must remain in history.
        let item = makeItem()
        let checkIn = StockService.checkIn(item: item, qty: 5, exp: .now, context: context)
        try StockService.checkOut(item: item, qty: 3, context: context)

        XCTAssertEqual(item.onHandTotal, 2)

        XCTAssertThrowsError(try StockService.remove(checkIn, context: context)) { error in
            XCTAssertTrue(error is StockServiceError)
        }

        XCTAssertEqual(item.onHandTotal, 2, "a failed remove must not partially reverse anything")
        XCTAssertTrue(item.transactions.contains { $0.id == checkIn.id }, "the transaction must remain if it couldn't be safely removed")
    }

    func testEditCheckInQuantityUpdatesBalanceAtomically() throws {
        let item = makeItem()
        let exp = Date(timeIntervalSince1970: 2_000_000_000)
        let transaction = StockService.checkIn(item: item, qty: 5, exp: exp, context: context)

        try StockService.edit(transaction, newQty: 9, newExp: exp, context: context)

        XCTAssertEqual(item.onHandTotal, 9)
        XCTAssertEqual(item.lots.count, 1)
    }

    func testEditThrowsAndLeavesBalanceUntouchedWhenNewQuantityExceedsAvailableStock() throws {
        // Regression test for the validate-then-apply fix: the old "reverse, try apply, catch and
        // try?-restore" pattern could leave stock half-reversed if the restore itself silently
        // failed. Editing a check-out up to a quantity the item can no longer cover must fail
        // before mutating anything, leaving both the balance and the original transaction intact.
        let item = makeItem()
        StockService.checkIn(item: item, qty: 10, exp: .now, context: context)
        let transactions = try StockService.checkOut(item: item, qty: 4, context: context)
        let checkOut = transactions[0]

        XCTAssertEqual(item.onHandTotal, 6)

        XCTAssertThrowsError(try StockService.edit(checkOut, newQty: 100, newExp: checkOut.exp, context: context)) { error in
            XCTAssertTrue(error is StockServiceError)
        }

        XCTAssertEqual(item.onHandTotal, 6, "a failed edit must not partially reverse or apply anything")
        XCTAssertEqual(checkOut.qty, 4, "the original transaction must be untouched")
    }
}
