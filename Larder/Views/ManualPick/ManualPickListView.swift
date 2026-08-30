import SwiftUI

/// F3/F5: searchable fallback for both check-in and check-out. In check-out mode, only items
/// with stock on hand are searchable (FR-1.3). In check-in mode, a "+ Add new product" action
/// is always available, and a no-match search prompts adding the typed text as a new product.
struct ManualPickListView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: QuantitySheetMode
    let onSelect: (Item) -> Void
    var onAddNewProduct: ((String) -> Void)? = nil

    @State private var searchText = ""
    @State private var debouncedSearchText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mode == .checkOut ? "Check Out" : "Check In")
                    .font(LarderFont.screenTitle())
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(20)

            // searchText here is the live typed value (for "Add new product" and the empty-state
            // message text); the results view below filters against the debounced value.
            ManualPickResultsView(
                mode: mode,
                debouncedSearchText: debouncedSearchText,
                liveSearchText: searchText,
                onSelect: onSelect,
                onAddNewProduct: onAddNewProduct
            )

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

            TextField("Search name or barcode", text: $searchText)
                .padding(12)
                .background(Color.white)
                .overlay(Rectangle().strokeBorder(Color.larderDivider, lineWidth: 1))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)


        }
        .background(Color.larderBackground.ignoresSafeArea())
        .task(id: searchText) {
            // Debounce: at catalog scale, re-filtering the (already fully-synced) catalog on
            // every keystroke is avoidable work. `.task(id:)` cancels the previous sleep
            // automatically when `searchText` changes again before it elapses, so only a pause
            // in typing actually commits a new search.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
    }
}

/// Owns the actual result set. The whole (5,000-item-capped) catalog is already synced locally
/// via `CatalogStore` (ADR-0003), so this filters/sorts client-side in Swift rather than scoping a
/// SwiftData fetch predicate the way the old `@Query`-based version did — Firestore has no native
/// substring/`contains` query, so this was always going to be a client-side filter eventually;
/// the debounce above is what keeps that affordable at catalog scale.
private struct ManualPickResultsView: View {
    @Environment(CatalogStore.self) private var store

    let mode: QuantitySheetMode
    let debouncedSearchText: String
    let liveSearchText: String
    let onSelect: (Item) -> Void
    let onAddNewProduct: ((String) -> Void)?

    private var filteredItems: [Item] {
        var items = store.items
        if debouncedSearchText.count >= 1 {
            items = items.filter {
                $0.name.localizedStandardContains(debouncedSearchText)
                    || ($0.barcode?.localizedStandardContains(debouncedSearchText) ?? false)
            }
        }
        items = CatalogFiltering.manualPickFilteredItems(items, transactions: store.transactions, mode: mode)
        return items.sorted { $0.name < $1.name }
    }

    var body: some View {
        if filteredItems.isEmpty {
            VStack(spacing: 12) {
                Text(mode == .checkIn ? "No matches. Add \"\(liveSearchText)\" as a new product?" : "No matching items on hand.")
                    .foregroundStyle(Color.larderSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if mode == .checkIn, !liveSearchText.isEmpty, let onAddNewProduct {
                    SecondaryButton(title: "Add New Product") {
                        onAddNewProduct(liveSearchText)
                    }
                    .padding(.horizontal, 40)
                }
            }
            .padding(.top, 40)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            HubRow(item: item, transactions: store.transactions)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Color.larderDivider)
                    }
                }
            }
        }
    }
}
