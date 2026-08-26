import SwiftUI

/// Matches the reference design's bottom bar: 3 equal-width tabs, red underline + red label
/// on the active tab, gray otherwise.
struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.larderInk)
                .frame(height: 1)
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 6) {
                            Rectangle()
                                .fill(selection == tab ? Color.larderAccent : .clear)
                                .frame(height: 2)
                            Text(tab.rawValue)
                                .trackedUppercase()
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(selection == tab ? Color.larderAccent : Color.larderSecondaryText)
                                .padding(.bottom, 10)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 8)
        }
        .background(Color.larderBackground)
    }
}
