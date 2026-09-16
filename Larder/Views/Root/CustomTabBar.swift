import SwiftUI

/// Matches the reference design's bottom bar: 3 equal-width tabs (Settings lives behind the
/// top bar's gear icon instead, per the redesign), each with an icon over its label, navy
/// underline + navy icon/label on the active tab, gray otherwise. The active tab's navy
/// indicator sits flush on the same 1px line that separates this bar from the content above --
/// drawn as one shared `larderDivider` line behind the row, with the selected tab's own
/// (taller, opaque) indicator rectangle painting over its segment of it -- rather than as two
/// separately-spaced rules, so there's no gap between them.
struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 6) {
                        Rectangle()
                            .fill(selection == tab ? Color.larderAccent : .clear)
                            .frame(height: 2)
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                        Text(tab.rawValue)
                            .trackedUppercase()
                            .font(.publicSans(size: 12, weight: .bold))
                            .padding(.bottom, 10)
                    }
                    .foregroundStyle(selection == tab ? Color.larderAccent : Color.larderSecondaryText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(alignment: .top) {
            Rectangle()
                .fill(Color.larderDivider)
                .frame(height: 1)
        }
        .background(Color.larderBackground)
    }
}
