import Foundation

/// Shared day-granularity relative-date math and phrasing, replacing what the architecture
/// review flagged as the same `Calendar.dateComponents([.day], ...)` arithmetic and "today"/
/// "in N days"/"N days ago" label logic reimplemented independently in `Lot`, `ItemDetailView`,
/// `HubRow`, `StockListView`, and `Badges.swift`'s `ExpiryBadge`.
///
/// Foundation's native `Date.RelativeFormatStyle` (`.formatted(.relative(presentation:))`) was
/// considered, per the `swift-formatstyle` skill's guidance to prefer built-in `FormatStyle` over
/// manual formatting — but every call site here embeds the relative label inside a larger
/// compound string (e.g. "best before 2026-09-01 · in 7 days"), which that skill's own review
/// checklist flags as unsuitable for the native relative formatter without also localizing the
/// whole surrounding sentence. This app has no localization infrastructure yet (no String
/// Catalog, English-only throughout), so that's a separate, larger effort than this dedup pass.
/// Keeping the app's existing exact phrasing here, just in one place, is the smallest fix that
/// addresses the actual duplication.
extension Date {
    /// Whole calendar days from the start of today to the start of this date's day — negative
    /// if `self` is in the past. Both endpoints are normalized to `startOfDay` first, so this is
    /// calendar-day distance, not elapsed 24-hour periods.
    var daysFromToday: Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: .now),
            to: calendar.startOfDay(for: self)
        ).day ?? 0
    }

    /// "today" / "in N days" / "N days ago".
    var relativeDayLabel: String {
        let days = daysFromToday
        if days == 0 { return "today" }
        if days < 0 { return "\(-days) days ago" }
        return "in \(days) days"
    }
}

extension Optional where Wrapped == Date {
    /// "2026-09-01" for a dated `Lot`/`Transaction.exp`, "no expiration date" for one checked in
    /// against an `Item.noExpirationDate == true` product. The one shared phrasing for every
    /// list/detail row that shows a lot's or transaction's optional best-before date.
    var formattedExpirationDate: String {
        guard let self else { return "no expiration date" }
        return self.formatted(.iso8601.year().month().day())
    }
}
