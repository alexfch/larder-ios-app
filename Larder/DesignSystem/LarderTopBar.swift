import SwiftUI

/// Shared accent-filled top bar for the main tabs (Check Out/Check In/Stock): the "LARDER"
/// wordmark plus a settings gear, replacing the previous per-screen eyebrow+title header
/// (`ScreenHeader`) on those screens. `.ignoresSafeArea(edges: .top)` at the call site lets the
/// accent fill reach the very top of the screen, matching the design's status-bar-colored strip.
/// Uses SF Symbols in place of the design's hand-drawn SVG icons -- the idiomatic iOS equivalent,
/// not a literal trace of the source markup.
struct LarderTopBar: View {
    let onSettings: () -> Void

    var body: some View {
        HStack {
            Text("LARDER")
                .font(.system(size: 13, weight: .bold))
                .tracking(2.2)
                .foregroundStyle(Color.larderOnAccent)
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.larderOnAccent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            Color.larderAccent.ignoresSafeArea(edges: .top)
        }
    }
}
