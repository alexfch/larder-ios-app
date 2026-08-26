import SwiftUI

/// The eyebrow + big title pattern used at the top of each hub/list screen,
/// e.g. "PANTRY · TUE 25 AUG 2026" over "CHECK OUT".
struct ScreenHeader: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    init(eyebrow: String, title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> some View = { EmptyView() }) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow)
                        .trackedUppercase()
                        .font(LarderFont.eyebrow())
                        .foregroundStyle(Color.larderSecondaryText)
                    Text(title)
                        .font(LarderFont.screenTitle())
                        .foregroundStyle(Color.larderInk)
                }
                Spacer()
                trailing
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.larderSecondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
}

/// Today's date formatted like "TUE 25 AUG 2026" for the eyebrow line.
func todayEyebrowDate() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE d MMM yyyy"
    return formatter.string(from: .now).uppercased()
}
