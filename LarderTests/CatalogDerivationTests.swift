import XCTest
@testable import Larder

/// Direct coverage for `CatalogDerivation` — the client-side engine (ADR-0003) that turns the
/// append-only `Transaction` log into batches, on-hand totals, and earliest-best-before. The
/// existing suite exercises it only indirectly through `StockService`/`CatalogFiltering`.
final class CatalogDerivationTests: XCTestCase {

    private let itemId = "item-1"
    private let otherItemId = "item-2"

    private func day(_ offsetDays: Int) -> Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: Double(offsetDays) * 86_400))
    }

    private func checkIn(_ qty: Double, on date: Date, item: String? = nil) -> Transaction {
        Transaction(itemId: item ?? itemId, action: .checkIn, qty: qty, exp: date)
    }

    private func checkOut(_ qty: Double, on date: Date, item: String? = nil) -> Transaction {
        Transaction(itemId: item ?? itemId, action: .checkOut, qty: qty, exp: date)
    }

    private func adjust(_ signedQty: Double, on date: Date, item: String? = nil) -> Transaction {
        Transaction(itemId: item ?? itemId, action: .adjust, qty: signedQty, exp: date)
    }

    // MARK: lot grouping

    func testTransactionsSharingAnExpDateCollapseIntoOneLot() {
        let date = day(10)
        let lots = CatalogDerivation.lots(itemId: itemId, transactions: [checkIn(4, on: date), checkIn(3, on: date)])
        XCTAssertEqual(lots.count, 1)
        XCTAssertEqual(lots.first?.qty, 7)
        XCTAssertEqual(lots.first?.exp, date)
    }

    func testTransactionsAtDifferentTimesOfTheSameCalendarDayStillGroup() {
        // `exp` timestamps are normalized to `startOfDay`, so 01:00 and 09:00 on the same local
        // date are one lot, not two.
        let startOfSomeDay = Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: 30 * 86_400))
        let earlyHours = startOfSomeDay.addingTimeInterval(3_600)
        let midMorning = startOfSomeDay.addingTimeInterval(9 * 3_600)
        let lots = CatalogDerivation.lots(itemId: itemId, transactions: [checkIn(2, on: earlyHours), checkIn(5, on: midMorning)])
        XCTAssertEqual(lots.count, 1)
        XCTAssertEqual(lots.first?.qty, 7)
    }

    func testFullyConsumedLotIsDroppedFromTheBatchList() {
        let date = day(5)
        let transactions = [checkIn(6, on: date), checkOut(6, on: date)]
        XCTAssertEqual(CatalogDerivation.lots(itemId: itemId, transactions: transactions).count, 0)
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: itemId, transactions: transactions), 0)
    }

    func testRawLotTotalsKeepsZeroedGroupsThatLotsDrops() {
        let date = day(5)
        let transactions = [checkIn(6, on: date), checkOut(6, on: date)]
        let raw = CatalogDerivation.rawLotTotals(itemId: itemId, transactions: transactions)
        XCTAssertEqual(raw[date], 0, "raw totals retain the zeroed group for feasibility checks")
        XCTAssertEqual(CatalogDerivation.lots(itemId: itemId, transactions: transactions).count, 0)
    }

    func testDerivationIsScopedToTheRequestedItem() {
        let date = day(3)
        let transactions = [checkIn(4, on: date), checkIn(99, on: date, item: otherItemId)]
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: itemId, transactions: transactions), 4)
    }

    // MARK: totals & ordering

    func testEarliestBestBeforeIsTheMinimumLotDateStillOnHand() {
        let older = day(2)
        let newer = day(20)
        let transactions = [checkIn(1, on: older), checkIn(1, on: newer)]
        XCTAssertEqual(CatalogDerivation.earliestBestBefore(itemId: itemId, transactions: transactions), older)
    }

    func testEarliestBestBeforeSkipsAFullyConsumedEarlierLot() {
        let older = day(2)
        let newer = day(20)
        let transactions = [checkIn(3, on: older), checkOut(3, on: older), checkIn(1, on: newer)]
        XCTAssertEqual(CatalogDerivation.earliestBestBefore(itemId: itemId, transactions: transactions), newer)
    }

    func testSortedLotsAreOrderedByExpiryAscending() {
        let far = day(30), soon = day(1), mid = day(15)
        let lots = CatalogDerivation.sortedLots(itemId: itemId, transactions: [checkIn(1, on: far), checkIn(1, on: soon), checkIn(1, on: mid)])
        XCTAssertEqual(lots.map(\.exp), [soon, mid, far])
    }

    func testSortedTransactionsAreOrderedByOccurredAtDescending() {
        let date = day(10)
        let first = Transaction(itemId: itemId, action: .checkIn, qty: 1, exp: date, occurredAt: Date(timeIntervalSince1970: 1_000))
        let second = Transaction(itemId: itemId, action: .checkIn, qty: 1, exp: date, occurredAt: Date(timeIntervalSince1970: 2_000))
        let ordered = CatalogDerivation.sortedTransactions(itemId: itemId, transactions: [first, second])
        XCTAssertEqual(ordered.map(\.id), [second.id, first.id])
    }

    // MARK: adjust semantics

    func testNegativeAdjustmentReducesTheLotTotal() {
        let date = day(5)
        let transactions = [checkIn(10, on: date), adjust(-4, on: date)]
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: itemId, transactions: transactions), 6)
    }

    func testPositiveAdjustmentIncreasesTheLotTotal() {
        let date = day(5)
        let transactions = [checkIn(10, on: date), adjust(3, on: date)]
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: itemId, transactions: transactions), 13)
    }

    // MARK: lotsByItem parity

    func testLotsByItemSummaryMatchesPerItemDerivation() {
        let soon = day(3)
        let later = day(40)
        let transactions = [
            checkIn(5, on: soon), checkIn(2, on: later),
            checkIn(8, on: day(1), item: otherItemId)
        ]

        let summaries = CatalogDerivation.lotsByItem(transactions: transactions)

        XCTAssertEqual(summaries[itemId]?.onHandTotal, CatalogDerivation.onHandTotal(itemId: itemId, transactions: transactions))
        XCTAssertEqual(summaries[itemId]?.earliestBestBefore, CatalogDerivation.earliestBestBefore(itemId: itemId, transactions: transactions))
        XCTAssertEqual(summaries[itemId]?.isExpiringSoon, true, "a lot 3 days out is within the 14-day window")
        XCTAssertEqual(summaries[otherItemId]?.onHandTotal, 8)
    }

    func testLotsByItemExpiringSoonIsFalseWhenAllLotsAreBeyond14Days() {
        let summaries = CatalogDerivation.lotsByItem(transactions: [checkIn(1, on: day(30))])
        XCTAssertEqual(summaries[itemId]?.isExpiringSoon, false)
    }

    func testLotsByItemTreatsAPastDateAsExpiringSoon() {
        // FR-5.1: the expiry badge covers "within 14 days or already past its date".
        let summaries = CatalogDerivation.lotsByItem(transactions: [checkIn(1, on: day(-5))])
        XCTAssertEqual(summaries[itemId]?.isExpiringSoon, true)
    }
}
