import SwiftUI
import SwiftData

/// F1: opens by default; lists the 5 items nearest their earliest best-before date.
struct CheckOutHubView: View {
    @Query(sort: \Item.name) private var allItems: [Item]

    @State private var selectedItem: Item?
    @State private var showScanner = false
    @State private var showManualPick = false
    @State private var scannedUnmatchedItem: Item?

    private var shortlist: [Item] {
        allItems
            .filter { $0.onHandTotal > 0 && $0.earliestBestBefore != nil }
            .sorted { ($0.earliestBestBefore ?? .distantFuture) < ($1.earliestBestBefore ?? .distantFuture) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: "Pantry · \(todayEyebrowDate())",
                title: "Check Out",
                subtitle: "Scan what you are taking, or pick it from the list."
            )

            Divider().overlay(Color.larderDivider)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Use these first — earliest best before")
                        .trackedUppercase()
                        .font(LarderFont.eyebrow())
                        .foregroundStyle(Color.larderSecondaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)

                    if shortlist.isEmpty {
                        Text("Nothing due out yet. Check something in first.")
                            .foregroundStyle(Color.larderSecondaryText)
                            .padding(20)
                    } else {
                        ForEach(shortlist) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                HubRow(item: item)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Color.larderDivider)
                        }
                    }
                }
            }

            VStack(spacing: 10) {
                PrimaryButton(title: "Scan") { showScanner = true }
                SecondaryButton(title: "Manual") { showManualPick = true }
            }
            .padding(20)
        }
        .background(Color.larderBackground.ignoresSafeArea())
        .sheet(item: $selectedItem) { item in
            QuantitySheetView(item: item, mode: .checkOut, preselectedLot: item.sortedLots.first)
        }
        .sheet(isPresented: $showManualPick) {
            ManualPickListView(mode: .checkOut) { item in
                showManualPick = false
                selectedItem = item
            }
        }
        .sheet(isPresented: $showScanner) {
            BarcodeScannerView { code in
                showScanner = false
                if let match = allItems.first(where: { $0.barcode == code }) {
                    selectedItem = match
                }
            }
        }
    }
}

/// Shared list row for the Check Out / Check In hub screens.
struct HubRow: View {
    let item: Item
    var quantityOverride: String? = nil
    var isHighlighted: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(LarderFont.rowTitle())
                if let earliest = item.earliestBestBefore {
                    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: earliest)).day ?? 0
                    Text("best before \(earliest.formatted(.iso8601.year().month().day())) · \(relativeLabel(days))")
                        .font(LarderFont.rowSubtitle())
                        .foregroundStyle(Color.larderSecondaryText)
                }
            }
            Spacer()
            Text(quantityOverride ?? item.formattedQuantity(item.onHandTotal))
                .font(LarderFont.quantityValue())
                .foregroundStyle(isHighlighted ? Color.larderAccent : Color.larderInk)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func relativeLabel(_ days: Int) -> String {
        if days == 0 { return "today" }
        if days < 0 { return "\(-days) days ago" }
        return "in \(days) days"
    }
}
