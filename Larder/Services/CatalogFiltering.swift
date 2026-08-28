import Foundation

/// Pure filter/sort rules previously inlined as private computed properties in
/// `StockResultsView`, `CheckOutHubView`, and `ManualPickResultsView` — extracted per the
/// architecture review so each rule has one, independently testable implementation instead of
/// living only inside a view body where it can't be exercised without instantiating SwiftUI.
enum CatalogFiltering {

    /// Stock list ordering (FR-5.1): soonest-expiring first, items with no batches at all last,
    /// alphabetical among themselves. Optionally restricted to items with at least one
    /// expiring-soon batch.
    static func stockVisibleItems(_ items: [Item], expiringOnly: Bool) -> [Item] {
        var result = items
        if expiringOnly {
            result = result.filter { item in item.sortedLots.contains { $0.isExpiringSoon } }
        }
        return result.sorted { lhs, rhs in
            switch (lhs.earliestBestBefore, rhs.earliestBestBefore) {
            case let (lhsDate?, rhsDate?): return lhsDate < rhsDate
            case (nil, nil): return lhs.name < rhs.name
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    /// Check Out hub shortlist (F1): up to `limit` items nearest their earliest best-before date,
    /// excluding items with no stock on hand or no batches at all.
    static func checkOutShortlist(_ items: [Item], limit: Int = 5) -> [Item] {
        Array(
            items
                .filter { $0.onHandTotal > 0 && $0.earliestBestBefore != nil }
                .sorted { ($0.earliestBestBefore ?? .distantFuture) < ($1.earliestBestBefore ?? .distantFuture) }
                .prefix(limit)
        )
    }

    /// Manual Pick's check-out-mode restriction (FR-1.3): only items with stock on hand are
    /// selectable; check-in mode has no such restriction.
    static func manualPickFilteredItems(_ items: [Item], mode: QuantitySheetMode) -> [Item] {
        mode == .checkOut ? items.filter { $0.onHandTotal > 0 } : items
    }
}
