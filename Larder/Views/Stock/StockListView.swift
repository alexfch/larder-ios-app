import SwiftUI
import SwiftData

/// FR-5.1: every item, sorted soonest-expiring first (no-batch items last), with search and
/// an "Expiring ≤ 14 days" filter. Hosts the entry point into a stock-take (FR-7.1).
struct StockListView: View {
    @Query private var allItems: [Item]

    @State private var searchText = ""
    @State private var expiringOnly = false
    @State private var selectedItem: Item?
    @State private var showCountSession = false

    private var expiringSoonCount: Int {
        allItems.filter { item in item.sortedLots.contains { $0.isExpiringSoon } }.count
    }

    private var visibleItems: [Item] {
        var items = allItems
        if searchText.count >= 2 {
            let lower = searchText.lowercased()
            items = items.filter { $0.name.lowercased().contains(lower) || ($0.barcode?.contains(searchText) ?? false) }
        }
        if expiringOnly {
            items = items.filter { item in item.sortedLots.contains { $0.isExpiringSoon } }
        }
        return items.sorted { lhs, rhs in
            switch (lhs.earliestBestBefore, rhs.earliestBestBefore) {
            case let (l?, r?): return l < r
            case (nil, nil): return lhs.name < rhs.name
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: "In the pantry", title: "Stock") {
                SecondaryButton(title: "Count") { showCountSession = true }
                    .frame(width: 96)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Search name or barcode", text: $searchText)
                    .padding(12)
                    .background(Color.white)
                    .overlay(Rectangle().strokeBorder(Color.larderDivider, lineWidth: 1))

                Button {
                    expiringOnly.toggle()
                } label: {
                    Text("Expiring ≤ 14 days (\(expiringSoonCount))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(expiringOnly ? .white : Color.larderInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(expiringOnly ? Color.larderInk : Color.clear)
                        .overlay(Rectangle().strokeBorder(Color.larderInk, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider().overlay(Color.larderDivider)

            if visibleItems.isEmpty {
                Spacer()
                Text("No items match.")
                    .foregroundStyle(Color.larderSecondaryText)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(visibleItems) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                StockRow(item: item)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Color.larderDivider)
                        }
                    }
                }
            }
        }
        .background(Color.larderBackground.ignoresSafeArea())
        .sheet(item: $selectedItem) { item in
            NavigationStack { ItemDetailView(item: item) }
        }
        .sheet(isPresented: $showCountSession) {
            CountSessionView()
        }
    }
}

struct StockRow: View {
    let item: Item

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ItemThumbnail(photoData: item.photoData, monogram: item.monogram)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(LarderFont.rowTitle())
                Text(item.barcode ?? "no barcode")
                    .font(LarderFont.rowSubtitle())
                    .foregroundStyle(Color.larderSecondaryText)
                HStack(spacing: 8) {
                    if let earliest = item.earliestBestBefore {
                        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: earliest)).day ?? 0
                        ExpiryBadge(date: earliest, daysUntil: days)
                    }
                    if item.lots.count > 1 {
                        OutlineTag(text: "\(item.lots.count) batches")
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(quantityValueString(item))
                    .font(LarderFont.quantityValue())
                Text(quantityUnitString(item))
                    .font(LarderFont.quantityUnit())
                    .foregroundStyle(Color.larderSecondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func quantityValueString(_ item: Item) -> String {
        let full = item.formattedQuantity(item.onHandTotal)
        return full.components(separatedBy: " ").first ?? full
    }

    private func quantityUnitString(_ item: Item) -> String {
        let full = item.formattedQuantity(item.onHandTotal)
        let parts = full.components(separatedBy: " ")
        return parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
    }
}
