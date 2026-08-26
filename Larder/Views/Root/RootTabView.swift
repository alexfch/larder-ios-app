import SwiftUI

struct RootTabView: View {
    @State private var selection: AppTab = .checkOut

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selection {
                case .checkOut:
                    CheckOutHubView()
                case .checkIn:
                    CheckInHubView()
                case .stock:
                    StockListView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CustomTabBar(selection: $selection)
        }
        .background(Color.larderBackground.ignoresSafeArea())
    }
}
