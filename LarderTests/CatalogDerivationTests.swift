import XCTest
@testable import Larder

/// `CatalogDerivation` is the client-side replacement for SwiftData's `Item.lots` relationship
/// (ADR-0003): every on-hand total, batch list, and earliest-best-before in the app is derived
/// here from raw `Transaction` documents. It was previously covered only indirectly through
/// `StockService` and `CatalogFiltering`; these tests exercise it directly, including the
/// `lotsByItem` one-pass grouping that the filter/sort hot path depends on.
final class CatalogDerivationTests: XCTestCase {

    private let itemId = "item-1"

    private func day(_ offsetDays: Int) -> Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: Double(offsetDays) * 86_400))
    }

    private func checkIn(qty: Double, exp: Date) -> Transaction {
        Transaction(itemId: itemId, action: .checkIn, qty: qty, exp: exp)
    }

    private func checkOut(qty: Double, exp: Date) -> Transaction {
        Transaction(itemId: itemId, action: .checkOut, qty: qty, exp: exp)
    }

    // MARK: lots / onHandTotal / earliestBestBefore

    func testLotsGroupTransactionsByExpiryDayAndNetTheirQuantities() {
        let soon = day(3)
        let later = day(20)
        let transactions = [
            checkIn(qty: 5, exp: soon),
            checkIn(qty: 2, exp: soon),
            checkOut(qty: 1, exp: soon),
            checkIn(qty: 10, exp: later)
        ]

        let lots = CatalogDerivation.sortedLots(itemId: itemId, transactions: transactions)

        XCTAssertEqual(lots.map(\.qty), [6, 10], "5 + 2 − 1 on the earliest day, 10 on the later day")
        XCTAssertEqual(lots.map(\.exp), [soon, later], "sorted earliest-first")
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: itemId, transactions: transactions), 16)
        XCTAssertEqual(CatalogDerivation.earliestBestBefore(itemId: itemId, transactions: transactions), soon)
    }

    func testFullyConsumedLotsAreDroppedFromTheBatchList() {
        let exp = day(5)
        let transactions = [checkIn(qty: 4, exp: exp), checkOut(qty: 4, exp: exp)]

        XCTAssertTrue(CatalogDerivation.lots(itemId: itemId, transactions: transactions).isEmpty)
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: itemId, transactions: transactions), 0)
        XCTAssertNil(CatalogDerivation.earliestBestBefore(itemId: itemId, transactions: transactions))
    }

    func testRawLotTotalsKeepNonPositiveGroupingsForFeasibilityChecks() {
        let exp = day(5)
        let transactions = [checkIn(qty: 2, exp: exp), checkOut(qty: 5, exp: exp)]

        let raw = CatalogDerivation.rawLotTotals(itemId: itemId, transactions: transactions)

        XCTAssertEqual(raw[Calendar.current.startOfDay(for: exp)], -3, "raw totals expose the overdraw; lots() would hide it")
        XCTAssertTrue(CatalogDerivation.lots(itemId: itemId, transactions: transactions).isEmpty)
    }

    func testAdjustmentQuantityIsAppliedWithItsOwnSign() {
        let exp = day(5)
        let positive = [checkIn(qty: 5, exp: exp), Transaction(itemId: itemId, action: .adjust, qty: 3, exp: exp)]
        let negative = [checkIn(qty: 5, exp: exp), Transaction(itemId: itemId, action: .adjust, qty: -2, exp: exp)]

        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: itemId, transactions: positive), 8)
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: itemId, transactions: negative), 3)
    }

    func testDerivationIgnoresTransactionsBelongingToOtherItems() {
        let exp = day(5)
        let transactions = [
            checkIn(qty: 5, exp: exp),
            Transaction(itemId: "other-item", action: .checkIn, qty: 99, exp: exp)
        ]

        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: itemId, transactions: transactions), 5)
    }

    func testSortedTransactionsAreNewestFirstByOccurredAt() {
        let exp = day(5)
        let old = Transaction(itemId: itemId, action: .checkIn, qty: 1, exp: exp, occurredAt: Date(timeIntervalSince1970: 1_000))
        let new = Transaction(itemId: itemId, action: .checkOut, qty: 1, exp: exp, occurredAt: Date(timeIntervalSince1970: 2_000))

        let sorted = CatalogDerivation.sortedTransactions(itemId: itemId, transactions: [old, new])

        XCTAssertEqual(sorted.map(\.id), [new.id, old.id])
    }

    // MARK: lotsByItem — the batched one-pass summary used by CatalogFiltering

    func testLotsByItemSummarizesEveryItemInOnePass() {
        let expiringSoon = day(7)
        let notSoon = day(40)
        let transactions = [
            Transaction(itemId: "a", action: .checkIn, qty: 3, exp: expiringSoon),
            Transaction(itemId: "b", action: .checkIn, qty: 8, exp: notSoon),
            Transaction(itemId: "b", action: .checkOut, qty: 1, exp: notSoon)
        ]

        let summaries = CatalogDerivation.lotsByItem(transactions: transactions)

        XCTAssertEqual(summaries["a"]?.onHandTotal, 3)
        XCTAssertEqual(summaries["a"]?.isExpiringSoon, true, "7 days out is within the 14-day window")
        XCTAssertEqual(summaries["b"]?.onHandTotal, 7)
        XCTAssertEqual(summaries["b"]?.isExpiringSoon, false, "40 days out is outside the window")
        XCTAssertEqual(summaries["b"]?.earliestBestBefore, notSoon)
    }

    func testLotsByItemTreatsExactlyFourteenDaysAsExpiringSoon() {
        let boundary = day(14)
        let transactions = [Transaction(itemId: "a", action: .checkIn, qty: 1, exp: boundary)]

        XCTAssertEqual(CatalogDerivation.lotsByItem(transactions: transactions)["a"]?.isExpiringSoon, true)
    }

    func testLotsByItemOmitsItemsWhoseEveryLotIsFullyConsumed() {
        let exp = day(5)
        let transactions = [
            Transaction(itemId: "a", action: .checkIn, qty: 2, exp: exp),
            Transaction(itemId: "a", action: .checkOut, qty: 2, exp: exp)
        ]

        let summary = CatalogDerivation.lotsByItem(transactions: transactions)["a"]

        XCTAssertEqual(summary?.onHandTotal, 0)
        XCTAssertNil(summary?.earliestBestBefore)
        XCTAssertEqual(summary?.isExpiringSoon, false)
    }
}
