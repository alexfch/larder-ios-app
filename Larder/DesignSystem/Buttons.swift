import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .trackedUppercase()
                .font(LarderFont.buttonLabel())
                .foregroundStyle(Color.larderOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .background(isEnabled ? Color.larderAccent : Color.larderAccent.opacity(0.4))
        .disabled(!isEnabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .trackedUppercase()
                .font(LarderFont.buttonLabel())
                .foregroundStyle(isEnabled ? Color.larderInk : Color.larderInk.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .overlay(
            Rectangle()
                .strokeBorder(isEnabled ? Color.larderInk : Color.larderInk.opacity(0.35), lineWidth: 2)
        )
        .disabled(!isEnabled)
    }
}
