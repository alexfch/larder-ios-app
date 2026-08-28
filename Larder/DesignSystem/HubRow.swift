import SwiftUI

/// Shared list row for the Check Out, Check In, and Manual Pick screens. Previously defined
/// inside `CheckOutHubView.swift` — a hidden-coupling-via-file-location smell flagged by the
/// architecture review, since `ManualPickListView` (a different screen) also depends on it.
struct HubRow: View {
    let item: Item
    var quantityOverride: String? = nil
    var isHighlighted: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(LarderFont.rowTitle())
                if let earliest = item.earliestBestBefore {
                    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: earliest)).day ?? 0
                    Text("best before \(earliest.formatted(.iso8601.year().month().day())) · \(relativeLabel(days))")
                        .font(LarderFont.rowSubtitle())
                        .foregroundStyle(Color.larderSecondaryText)
                }
            }
            Spacer()
            Text(quantityOverride ?? item.formattedQuantity(item.onHandTotal))
                .font(LarderFont.quantityValue())
                .foregroundStyle(isHighlighted ? Color.larderAccent : Color.larderInk)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func relativeLabel(_ days: Int) -> String {
        if days == 0 { return "today" }
        if days < 0 { return "\(-days) days ago" }
        return "in \(days) days"
    }
}
