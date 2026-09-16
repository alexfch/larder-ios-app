import SwiftUI

/// Tappable chip for selecting a batch during check-out, e.g. "4 tins · 2026-09-10".
struct BatchChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.publicSans(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Color.larderOnAccent : Color.larderInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.larderAccent : Color.clear)
                .overlay(
                    Rectangle().strokeBorder(isSelected ? Color.larderAccent : Color.larderInk, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
