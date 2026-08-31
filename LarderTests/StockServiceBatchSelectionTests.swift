import XCTest
@testable import Larder

/// FR-2.2 — check-out draws from batches oldest-first, or from a batch the user picks, cascading
/// to the next-earliest batch when the request exceeds the chosen one. The existing
/// `StockServiceTests` cover the default oldest-first path; these cover the explicit
/// `preferredLot` selection and its cascade, plus `applyAdjustment` / `canApplyAdjustment`
/// (FR-7.3) which had no direct coverage.
@MainActor
final class StockServiceBatchSelectionTests: XCTestCase {
    var store: InMemoryCatalogStore!

    override func setUpWithError() throws {
        store = InMemoryCatalogStore()
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: Double(offset) * 86_400))
    }

    private func makeItemWithTwoLots() throws -> (item: Item, older: Date, newer: Date) {
        let item = Item(name: "Tinned Tomatoes", kind: .unit, noun: "tin")
        try store.addItem(item)
        let older = day(2)
        let newer = day(20)
        try StockService.checkIn(itemId: item.id, qty: 4, exp: older, store: store)
        try StockService.checkIn(itemId: item.id, qty: 6, exp: newer, store: store)
        return (item, older, newer)
    }

    private func lots(_ item: Item) -> [Lot] {
        CatalogDerivation.sortedLots(itemId: item.id, transactions: store.transactions)
    }

    // MARK: preferredLot selection

    func testCheckOutFromSelectedNewerBatchLeavesTheOlderBatchUntouched() throws {
        let (item, older, newer) = try makeItemWithTwoLots()
        let newerLot = try XCTUnwrap(lots(item).first { $0.exp == newer })

        try StockService.checkOut(itemId: item.id, qty: 3, preferredLot: newerLot, store: store)

        let remaining = lots(item)
        XCTAssertEqual(remaining.first { $0.exp == older }?.qty, 4, "older batch untouched — user chose the newer one")
        XCTAssertEqual(remaining.first { $0.exp == newer }?.qty, 3, "6 − 3 drawn from the selected batch")
    }

    func testCheckOutBeyondTheSelectedBatchCascadesToTheNextEarliest() throws {
        let (item, older, newer) = try makeItemWithTwoLots()
        let newerLot = try XCTUnwrap(lots(item).first { $0.exp == newer })

        // Ask for 8 from the newer batch, which only holds 6 — the remaining 2 must come from
        // the next-earliest (older) batch.
        let transactions = try StockService.checkOut(itemId: item.id, qty: 8, preferredLot: newerLot, store: store)

        XCTAssertEqual(transactions.count, 2, "one movement per batch drawn from")
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: item.id, transactions: store.transactions), 2)
        XCTAssertEqual(lots(item).first?.exp, older)
        XCTAssertEqual(lots(item).first?.qty, 2, "4 − the 2 that spilled over from the newer batch")
    }

    func testCheckOutClearingABatchExactlyRemovesItFromTheBatchList() throws {
        let (item, older, newer) = try makeItemWithTwoLots()
        let olderLot = try XCTUnwrap(lots(item).first { $0.exp == older })

        try StockService.checkOut(itemId: item.id, qty: 4, preferredLot: olderLot, store: store)

        XCTAssertEqual(lots(item).map(\.exp), [newer], "the emptied older batch no longer appears")
    }

    func testCheckOutExceedingTotalStockThrowsAndWritesNothing() throws {
        let (item, _, _) = try makeItemWithTwoLots()

        XCTAssertThrowsError(try StockService.checkOut(itemId: item.id, qty: 20, store: store)) { error in
            XCTAssertTrue(error is StockServiceError)
        }
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: item.id, transactions: store.transactions), 10, "unchanged")
        XCTAssertEqual(store.transactions(for: item.id).count, 2, "only the two original check-ins")
    }

    // MARK: applyAdjustment / canApplyAdjustment (FR-7.3)

    func testApplyAdjustmentWritesOneSignedMovementAgainstTheEarliestBatchWithItsReason() throws {
        let (item, older, _) = try makeItemWithTwoLots()

        let adjustment = try StockService.applyAdjustment(itemId: item.id, delta: -3, reason: .spoiled, store: store)

        XCTAssertEqual(adjustment.action, .adjust)
        XCTAssertEqual(adjustment.qty, -3)
        XCTAssertEqual(adjustment.exp, older, "adjustments land on the earliest batch")
        XCTAssertEqual(adjustment.reasonTag, AdjustReason.spoiled.rawValue)
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: item.id, transactions: store.transactions), 7)
    }

    func testCanApplyAdjustmentRejectsADeltaThatWouldOverdrawTheEarliestBatch() throws {
        let (item, _, _) = try makeItemWithTwoLots()

        // The earliest batch holds 4; a −5 adjustment against it would take that lot negative.
        XCTAssertFalse(StockService.canApplyAdjustment(itemId: item.id, delta: -5, transactions: store.transactions))
        XCTAssertTrue(StockService.canApplyAdjustment(itemId: item.id, delta: -4, transactions: store.transactions))
        XCTAssertTrue(StockService.canApplyAdjustment(itemId: item.id, delta: 10, transactions: store.transactions))
    }

    // MARK: check-in date normalization (FR-2.1)

    func testCheckInNormalizesExpiryToTheStartOfDaySoSameDayCheckInsMerge() throws {
        let item = Item(name: "Rice", kind: .bulk, unit: "g")
        try store.addItem(item)
        let morning = try XCTUnwrap(Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: day(10)))
        let evening = try XCTUnwrap(Calendar.current.date(bySettingHour: 21, minute: 30, second: 0, of: day(10)))

        try StockService.checkIn(itemId: item.id, qty: 500, exp: morning, store: store)
        try StockService.checkIn(itemId: item.id, qty: 250, exp: evening, store: store)

        let lots = CatalogDerivation.sortedLots(itemId: item.id, transactions: store.transactions)
        XCTAssertEqual(lots.count, 1, "two check-ins on the same calendar day form one batch")
        XCTAssertEqual(lots.first?.qty, 750)
    }
}
