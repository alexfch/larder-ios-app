import XCTest
@testable import Larder

/// Covers FR-2.2's batch-selection rules for check-out (draw from a chosen batch, cascade the
/// shortfall to the next-earliest) and `StockService.edit` moving a movement to a different
/// batch date — paths the existing `StockServiceTests` doesn't touch (it only tests the default
/// FIFO order and quantity edits).
@MainActor
final class StockServiceBatchSelectionTests: XCTestCase {
    var store: InMemoryCatalogStore!

    override func setUpWithError() throws {
        store = InMemoryCatalogStore()
    }

    private func makeItem() -> Item {
        let item = Item(name: "Chopped Tomatoes", kind: .unit, noun: "tin")
        try? store.addItem(item)
        return item
    }

    private func day(_ offsetDays: Int) -> Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: Double(offsetDays) * 86_400))
    }

    private func lots(_ item: Item) -> [Lot] {
        CatalogDerivation.sortedLots(itemId: item.id, transactions: store.transactions)
    }

    private func qty(_ item: Item, onDay date: Date) -> Double {
        CatalogDerivation.rawLotTotals(itemId: item.id, transactions: store.transactions)[date] ?? 0
    }

    // MARK: preferred-batch selection (FR-2.2)

    func testCheckOutDrawsFromTheSelectedBatchNotTheEarliest() throws {
        let item = makeItem()
        try StockService.checkIn(itemId: item.id, qty: 3, exp: day(2), store: store)   // earliest
        try StockService.checkIn(itemId: item.id, qty: 5, exp: day(30), store: store)  // selected

        let selected = try XCTUnwrap(lots(item).first { $0.exp == day(30) })
        try StockService.checkOut(itemId: item.id, qty: 4, preferredLot: selected, store: store)

        XCTAssertEqual(qty(item, onDay: day(2)), 3, "the earliest batch is untouched when a later one is chosen")
        XCTAssertEqual(qty(item, onDay: day(30)), 1, "the selected batch absorbs the whole check-out")
    }

    func testCheckOutFromSelectedBatchCascadesShortfallToNextEarliest() throws {
        let item = makeItem()
        try StockService.checkIn(itemId: item.id, qty: 2, exp: day(1), store: store)   // earliest
        try StockService.checkIn(itemId: item.id, qty: 5, exp: day(10), store: store)  // selected
        try StockService.checkIn(itemId: item.id, qty: 9, exp: day(20), store: store)  // newest

        let selected = try XCTUnwrap(lots(item).first { $0.exp == day(10) })
        // Request 6 — one more than the selected batch holds.
        let created = try StockService.checkOut(itemId: item.id, qty: 6, preferredLot: selected, store: store)

        XCTAssertEqual(qty(item, onDay: day(10)), 0, "selected batch fully drained")
        XCTAssertEqual(qty(item, onDay: day(1)), 1, "shortfall of 1 drawn from the next-earliest batch")
        XCTAssertEqual(qty(item, onDay: day(20)), 9, "newest batch untouched")
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: item.id, transactions: store.transactions), 10)
        XCTAssertEqual(created.count, 2, "one transaction per batch drawn from, each tied to its batch date")
    }

    func testSelectedBatchThatFullyEmptiesIsRemovedFromTheBatchList() throws {
        let item = makeItem()
        try StockService.checkIn(itemId: item.id, qty: 4, exp: day(3), store: store)
        try StockService.checkIn(itemId: item.id, qty: 4, exp: day(9), store: store)

        let selected = try XCTUnwrap(lots(item).first { $0.exp == day(3) })
        try StockService.checkOut(itemId: item.id, qty: 4, preferredLot: selected, store: store)

        XCTAssertEqual(lots(item).map(\.exp), [day(9)], "an emptied batch no longer appears in the batch list")
    }

    func testCheckOutStillThrowsWhenTotalAcrossAllBatchesIsInsufficient() throws {
        let item = makeItem()
        try StockService.checkIn(itemId: item.id, qty: 2, exp: day(2), store: store)
        try StockService.checkIn(itemId: item.id, qty: 2, exp: day(8), store: store)

        let selected = try XCTUnwrap(lots(item).first)
        XCTAssertThrowsError(try StockService.checkOut(itemId: item.id, qty: 10, preferredLot: selected, store: store))
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: item.id, transactions: store.transactions), 4, "nothing drawn on a failed check-out")
    }

    // MARK: editing a movement's batch date (FR-6.1)

    func testEditingACheckInDateMovesItsQuantityToTheNewBatch() throws {
        let item = makeItem()
        let checkIn = try StockService.checkIn(itemId: item.id, qty: 5, exp: day(4), store: store)

        try StockService.edit(checkIn, newQty: 5, newExp: day(25), store: store)

        XCTAssertEqual(qty(item, onDay: day(4)), 0, "the original batch is emptied")
        XCTAssertEqual(qty(item, onDay: day(25)), 5, "the quantity now lives in the new batch")
        XCTAssertEqual(lots(item).map(\.exp), [day(25)])
    }
}
