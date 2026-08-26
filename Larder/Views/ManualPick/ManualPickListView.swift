import SwiftUI
import SwiftData

/// F3/F5: searchable fallback for both check-in and check-out. In check-out mode, only items
/// with stock on hand are searchable (FR-1.3). In check-in mode, a "+ Add new product" action
/// is always available, and a no-match search prompts adding the typed text as a new product.
struct ManualPickListView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Item.name) private var allItems: [Item]

    let mode: QuantitySheetMode
    let onSelect: (Item) -> Void
    var onAddNewProduct: ((String) -> Void)? = nil

    @State private var searchText = ""

    private var searchableItems: [Item] {
        mode == .checkOut ? allItems.filter { $0.onHandTotal > 0 } : allItems
    }

    private var filteredItems: [Item] {
        guard searchText.count >= 1 else { return searchableItems }
        let lower = searchText.lowercased()
        return searchableItems.filter {
            $0.name.lowercased().contains(lower) || ($0.barcode?.contains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mode == .checkOut ? "Check Out" : "Check In")
                    .font(LarderFont.screenTitle())
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(20)

            TextField("Search name or barcode", text: $searchText)
                .padding(12)
                .background(Color.white)
                .overlay(Rectangle().strokeBorder(Color.larderDivider, lineWidth: 1))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            if mode == .checkIn, let onAddNewProduct {
                Button {
                    onAddNewProduct(searchText)
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add new product")
                            .trackedUppercase()
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(Color.larderAccent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                Divider().overlay(Color.larderDivider)
            }

            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Text(mode == .checkIn ? "No matches. Add \"\(searchText)\" as a new product?" : "No matching items on hand.")
                        .foregroundStyle(Color.larderSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    if mode == .checkIn, !searchText.isEmpty, let onAddNewProduct {
                        SecondaryButton(title: "Add New Product") {
                            onAddNewProduct(searchText)
                        }
                        .padding(.horizontal, 40)
                    }
                }
                .padding(.top, 40)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                HubRow(item: item)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Color.larderDivider)
                        }
                    }
                }
            }
        }
        .background(Color.larderBackground.ignoresSafeArea())
    }
}
