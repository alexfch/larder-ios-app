import SwiftUI

/// Small red-bordered pill used for "N BATCHES" and similar tags.
struct OutlineTag: View {
    let text: String
    var color: Color = .larderAccent

    var body: some View {
        Text(text)
            .trackedUppercase()
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(color, lineWidth: 1)
            )
    }
}

/// Filled tag used for expiry dates, e.g. "2026-09-01 · in 7 days".
struct ExpiryBadge: View {
    let date: Date

    private var isSoon: Bool { date.daysFromToday <= 14 }

    var body: some View {
        Text("\(date.formatted(.iso8601.year().month().day())) · \(date.relativeDayLabel)")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isSoon ? Color.larderAccent : Color.larderSecondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSoon ? Color.larderExpiryBadgeBackground : Color.clear)
    }
}

/// Tappable chip for selecting a batch during check-out, e.g. "4 tins · 2026-09-10".
struct BatchChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color.larderInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.larderInk : Color.clear)
                .overlay(
                    Rectangle().strokeBorder(Color.larderInk, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
