import Foundation

/// Derives an item's batches, on-hand total, and earliest best-before from its `Transaction`
/// documents (ADR-0003) — the client-side counterpart to what used to be SwiftData's `Item.lots`
/// relationship. Pure functions over plain arrays, independently testable without Firestore.
enum CatalogDerivation {

    /// Signed effect of one transaction on the running total of the lot it names (`.checkIn`
    /// always adds; `.checkOut` always subtracts; `.adjust`'s `qty` is already signed).
    private static func signedEffect(_ transaction: Transaction) -> Double {
        switch transaction.action {
        case .checkIn: return transaction.qty
        case .checkOut: return -transaction.qty
        case .adjust: return transaction.qty
        }
    }

    /// Every `(exp date, running total)` pair for one item, including non-positive totals — used
    /// for feasibility checks (a lot's balance must never go negative), unlike `lots(...)` below
    /// which only returns what's actually still on the shelf. The `nil` key groups every
    /// transaction with no `exp` (a no-expiration item's check-ins) into one no-expiration lot,
    /// same as any other grouping key.
    static func rawLotTotals(itemId: String, transactions: [Transaction]) -> [Date?: Double] {
        var totals: [Date?: Double] = [:]
        for transaction in transactions where transaction.itemId == itemId {
            let day = transaction.exp.map { Calendar.current.startOfDay(for: $0) }
            totals[day, default: 0] += signedEffect(transaction)
        }
        return totals
    }

    /// The batches actually on the shelf for one item — zero/negative groupings are dropped
    /// (fully consumed, or a rounding artifact from floating-point summation).
    static func lots(itemId: String, transactions: [Transaction]) -> [Lot] {
        rawLotTotals(itemId: itemId, transactions: transactions)
            .filter { $0.value > 0.0001 }
            .map { Lot(itemId: itemId, qty: $0.value, exp: $0.key) }
    }

    /// Dated lots first (earliest first), any no-expiration lot last — there's no natural
    /// chronological position for "never expires" among dated batches, and pushing it to the end
    /// matches FIFO intuition: use up what has a clock ticking on it before what doesn't.
    static func sortedLots(itemId: String, transactions: [Transaction]) -> [Lot] {
        lots(itemId: itemId, transactions: transactions).sorted { lhs, rhs in
            switch (lhs.exp, rhs.exp) {
            case let (lhsExp?, rhsExp?): return lhsExp < rhsExp
            case (nil, nil): return false
            case (nil, _?): return false
            case (_?, nil): return true
            }
        }
    }

    static func onHandTotal(itemId: String, transactions: [Transaction]) -> Double {
        lots(itemId: itemId, transactions: transactions).reduce(0) { $0 + $1.qty }
    }

    /// nil when there's no stock at all *or* every lot on the shelf has no expiration date --
    /// both cases mean there's no best-before date to surface.
    static func earliestBestBefore(itemId: String, transactions: [Transaction]) -> Date? {
        lots(itemId: itemId, transactions: transactions).compactMap(\.exp).min()
    }

    static func sortedTransactions(itemId: String, transactions: [Transaction]) -> [Transaction] {
        transactions.filter { $0.itemId == itemId }.sorted { $0.occurredAt > $1.occurredAt }
    }

    /// Per-item lot summary — just the two values `CatalogFiltering` actually needs per item,
    /// precomputed once by `lotsByItem(transactions:)` rather than re-derived from scratch on
    /// every filter check and every sort comparison.
    struct ItemLotSummary {
        var onHandTotal: Double
        var earliestBestBefore: Date?
        var isExpiringSoon: Bool
    }

    /// Groups every item's lots in one pass over `transactions`, instead of the O(items ×
    /// transactions) cost of calling `lots(itemId:transactions:)` once per item — which, worse,
    /// is what a naive filter-then-sort was doing *per item, per sort comparison*, measured at
    /// ~5 seconds for a 5,000-item catalog. This is O(transactions) to build the grouping, then
    /// O(items) to summarize it.
    static func lotsByItem(transactions: [Transaction]) -> [String: ItemLotSummary] {
        var totalsByItem: [String: [Date?: Double]] = [:]
        for transaction in transactions {
            let day = transaction.exp.map { Calendar.current.startOfDay(for: $0) }
            totalsByItem[transaction.itemId, default: [:]][day, default: 0] += signedEffect(transaction)
        }

        var summaries: [String: ItemLotSummary] = [:]
        summaries.reserveCapacity(totalsByItem.count)
        for (itemId, totals) in totalsByItem {
            var onHandTotal = 0.0
            var earliest: Date?
            var isExpiringSoon = false
            for (exp, qty) in totals where qty > 0.0001 {
                onHandTotal += qty
                if let exp {
                    if earliest == nil || exp < earliest! { earliest = exp }
                    if exp.daysFromToday <= 14 { isExpiringSoon = true }
                }
            }
            summaries[itemId] = ItemLotSummary(onHandTotal: onHandTotal, earliestBestBefore: earliest, isExpiringSoon: isExpiringSoon)
        }
        return summaries
    }
}
