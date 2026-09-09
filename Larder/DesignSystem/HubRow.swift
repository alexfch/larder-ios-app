import SwiftUI

/// Shared "monogram + name/meta + qty/unit" row — matches the design's `inList`/recent-check-ins
/// row shape, used by Check In's list and Manual Pick. Previously defined inside
/// `CheckOutHubView.swift` — a hidden-coupling-via-file-location smell flagged by the architecture
/// review — and now also distinct from `CheckOutRow`, which adds the urgency bar/batch strip/tags
/// the Check Out hub's richer row needs and this one doesn't.
///
/// Takes `transactions` explicitly (ADR-0003): `earliestBestBefore`/`onHandTotal` are derived via
/// `CatalogDerivation` rather than read off a stored relationship.
struct HubRow: View {
    let item: Item
    let transactions: [Transaction]
    /// Overrides the displayed value (e.g. "+5" for a recent check-in's delta) -- `overrideUnit`
    /// must be passed alongside it, since the two always come as a pair.
    var overrideValue: String? = nil
    var overrideUnit: String? = nil
    /// Overrides the meta line -- e.g. Check In's recents show *that transaction's* check-in
    /// date, not the item's current earliest best-before, which is what this defaults to.
    var overrideMeta: String? = nil
    var isHighlighted: Bool = false

    private var metaText: String {
        if let overrideMeta { return overrideMeta }
        if let earliest = CatalogDerivation.earliestBestBefore(itemId: item.id, transactions: transactions) {
            return "\(earliest.formatted(.iso8601.year().month().day())) · \(earliest.relativeDayLabel)"
        }
        return CatalogDerivation.onHandTotal(itemId: item.id, transactions: transactions) > 0 ? "no best-before date" : "nothing on hand"
    }

    private var quantityParts: (value: String, unit: String) {
        if let overrideValue, let overrideUnit {
            return (overrideValue, overrideUnit)
        }
        let total = CatalogDerivation.onHandTotal(itemId: item.id, transactions: transactions)
        let full = item.formattedQuantity(total)
        let parts = full.components(separatedBy: " ")
        return (parts.first ?? full, parts.dropFirst().joined(separator: " "))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ItemThumbnail(
                photoData: nil,
                photoStorageRef: item.photoStorageRef,
                monogram: item.monogram,
                size: 48,
                monogramBackground: Color.larderMonoTones[item.monogramToneIndex]
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.larderInk)
                Text(metaText)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.larderSecondaryText)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(quantityParts.value)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(isHighlighted ? Color.larderAccent : Color.larderInk)
                Text(quantityParts.unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.larderSecondaryText)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
