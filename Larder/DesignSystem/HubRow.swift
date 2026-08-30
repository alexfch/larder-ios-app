import SwiftUI

/// Shared list row for the Check Out, Check In, and Manual Pick screens. Previously defined
/// inside `CheckOutHubView.swift` — a hidden-coupling-via-file-location smell flagged by the
/// architecture review, since `ManualPickListView` (a different screen) also depends on it.
///
/// Takes `transactions` explicitly (ADR-0003): `earliestBestBefore`/`onHandTotal` are derived via
/// `CatalogDerivation` rather than read off a stored relationship.
struct HubRow: View {
    let item: Item
    let transactions: [Transaction]
    var quantityOverride: String? = nil
    var isHighlighted: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(LarderFont.rowTitle())
                if let earliest = CatalogDerivation.earliestBestBefore(itemId: item.id, transactions: transactions) {
                    Text("best before \(earliest.formatted(.iso8601.year().month().day())) · \(earliest.relativeDayLabel)")
                        .font(LarderFont.rowSubtitle())
                        .foregroundStyle(Color.larderSecondaryText)
                }
            }
            Spacer()
            Text(quantityOverride ?? item.formattedQuantity(CatalogDerivation.onHandTotal(itemId: item.id, transactions: transactions)))
                .font(LarderFont.quantityValue())
                .foregroundStyle(isHighlighted ? Color.larderAccent : Color.larderInk)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
