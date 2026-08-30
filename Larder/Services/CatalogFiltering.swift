import Foundation

/// Pure filter/sort rules for the catalog. Takes `transactions` explicitly now (ADR-0003):
/// on-hand totals and earliest-best-before are derived from them via `CatalogDerivation` rather
/// than read off a stored `Item.lots` relationship. Every function here derives its per-item
/// summaries via `CatalogDerivation.lotsByItem` exactly once up front — not per item, and not
/// again inside a sort comparator — since that per-call-site re-derivation measured at ~5 seconds
/// for a 5,000-item catalog before this fix (see `CatalogScalePerformanceTests`).
enum CatalogFiltering {

    /// Stock list ordering (FR-5.1): soonest-expiring first, items with no batches at all last,
    /// alphabetical among themselves. Optionally restricted to items with at least one
    /// expiring-soon batch.
    static func stockVisibleItems(_ items: [Item], transactions: [Transaction], expiringOnly: Bool) -> [Item] {
        let summaries = CatalogDerivation.lotsByItem(transactions: transactions)

        var result = items
        if expiringOnly {
            result = result.filter { summaries[$0.id]?.isExpiringSoon ?? false }
        }
        return result.sorted { lhs, rhs in
            let lhsDate = summaries[lhs.id]?.earliestBestBefore
            let rhsDate = summaries[rhs.id]?.earliestBestBefore
            switch (lhsDate, rhsDate) {
            case let (lhsDate?, rhsDate?): return lhsDate < rhsDate
            case (nil, nil): return lhs.name < rhs.name
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    /// Check Out hub shortlist (F1): up to `limit` items nearest their earliest best-before date,
    /// excluding items with no stock on hand or no batches at all.
    static func checkOutShortlist(_ items: [Item], transactions: [Transaction], limit: Int = 5) -> [Item] {
        let summaries = CatalogDerivation.lotsByItem(transactions: transactions)

        return Array(
            items
                .filter { (summaries[$0.id]?.onHandTotal ?? 0) > 0 }
                .filter { summaries[$0.id]?.earliestBestBefore != nil }
                .sorted { (summaries[$0.id]?.earliestBestBefore ?? .distantFuture) < (summaries[$1.id]?.earliestBestBefore ?? .distantFuture) }
                .prefix(limit)
        )
    }

    /// Manual Pick's check-out-mode restriction (FR-1.3): only items with stock on hand are
    /// selectable; check-in mode has no such restriction.
    static func manualPickFilteredItems(_ items: [Item], transactions: [Transaction], mode: QuantitySheetMode) -> [Item] {
        guard mode == .checkOut else { return items }
        let summaries = CatalogDerivation.lotsByItem(transactions: transactions)
        return items.filter { (summaries[$0.id]?.onHandTotal ?? 0) > 0 }
    }
}
