import SwiftUI

/// Bordered, rounded search field used at the bottom of the Check Out/Check In hubs, replacing
/// the previous "Scan"/"Manual" button pair's `ManualPickListView` detour with in-place filtering
/// -- typing here is now how you browse the full catalog rather than opening a separate sheet.
struct InlineSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.larderSecondaryText)
            TextField(placeholder, text: $text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.larderInk)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.larderSecondaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color.larderSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.larderEdge, lineWidth: 1))
    }
}

/// A rounded, icon-trailing action button -- either solid-accent (`isOutlined: false`, e.g. "Scan
/// a barcode") or accent-outlined (`isOutlined: true`, e.g. "New"). Distinct from
/// `PrimaryButton`/`SecondaryButton`: those are full-width, uppercase, sharp-cornered labels-only;
/// this family matches the redesign's rounded, sentence-case, icon-paired action bar buttons.
struct InlineIconButton: View {
    let title: String
    let systemIcon: String
    var isOutlined: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: systemIcon)
                    .font(.system(size: 16, weight: .medium))
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .foregroundStyle(isOutlined ? Color.larderAccent : Color.larderOnAccent)
        }
        .background(isOutlined ? Color.clear : Color.larderAccent)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isOutlined ? Color.larderAccent : Color.clear, lineWidth: 2)
        )
    }
}
