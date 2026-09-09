import SwiftUI

@Observable
final class ToastCenter {
    var message: String?

    func show(_ message: String) {
        self.message = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if self.message == message {
                self.message = nil
            }
        }
    }
}

struct ToastOverlay: View {
    let message: String?

    var body: some View {
        VStack {
            Spacer()
            if let message {
                Text(message)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.larderToastForeground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.larderToastBackground)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: message)
        .allowsHitTesting(false)
    }
}
