import SwiftUI
import SwiftData

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

            // searchText here is the live typed value (for "Add new product" and the empty-state
            // message text); the results view below queries against the debounced value.
            ManualPickResultsView(
                mode: mode,
                debouncedSearchText: debouncedSearchText,
                liveSearchText: searchText,
                onSelect: onSelect,
                onAddNewProduct: onAddNewProduct
            )
        }
        .background(Color.larderBackground.ignoresSafeArea())
        .task(id: searchText) {
            // Debounce: at catalog scale, reconstructing the results view's @Query on every
            // keystroke is real, avoidable work. `.task(id:)` cancels the previous sleep
            // automatically when `searchText` changes again before it elapses, so only a pause
            // in typing actually commits a new search.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
    }
}

/// Owns the actual result set. `debouncedSearchText` (once non-empty) scopes this view's own
/// `@Query` to a name/barcode predicate — narrowing the *fetch* at the SwiftData layer instead of
/// loading the whole catalog into memory just to filter it in Swift, per the architecture
/// review's "unfiltered @Query" finding. `liveSearchText` is only for display text (the "Add new
/// product" prompt), so it doesn't need to wait for the debounce.
private struct ManualPickResultsView: View {
    @Query private var items: [Item]
    let mode: QuantitySheetMode
    let liveSearchText: String
    let onSelect: (Item) -> Void
    let onAddNewProduct: ((String) -> Void)?

    init(
        mode: QuantitySheetMode,
        debouncedSearchText: String,
        liveSearchText: String,
        onSelect: @escaping (Item) -> Void,
        onAddNewProduct: ((String) -> Void)?
    ) {
        self.mode = mode
        self.liveSearchText = liveSearchText
        self.onSelect = onSelect
        self.onAddNewProduct = onAddNewProduct

        let descriptor: FetchDescriptor<Item>
        if debouncedSearchText.count >= 1 {
            descriptor = FetchDescriptor<Item>(
                predicate: #Predicate<Item> { item in
                    item.name.localizedStandardContains(debouncedSearchText)
                        || (item.barcode?.localizedStandardContains(debouncedSearchText) ?? false)
                },
                sortBy: [SortDescriptor(\.name)]
            )
        } else {
            descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\.name)])
        }
        _items = Query(descriptor)
    }

    /// `onHandTotal` is computed from the `lots` relationship rather than a stored attribute, so
    /// the check-out "only items with stock on hand" rule can't be expressed in the fetch
    /// predicate above — it's a Swift-side filter over whatever the (already search-scoped) query
    /// returned.
    private var filteredItems: [Item] {
        CatalogFiltering.manualPickFilteredItems(items, mode: mode)
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
                            HubRow(item: item)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Color.larderDivider)
                    }
                }
            }
        }
    }
}
