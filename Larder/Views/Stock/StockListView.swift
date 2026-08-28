import SwiftUI
import SwiftData

/// FR-5.1: every item, sorted soonest-expiring first (no-batch items last), with search and
/// an "Expiring ≤ 14 days" filter. Hosts the entry point into a stock-take (FR-7.1).
struct StockListView: View {
    /// Single source of truth for "what's on screen right now," replacing two independent
    /// `@State` optionals/booleans each backing its own `.sheet()` modifier — the structural
    /// pattern the architecture review flagged as repeated across 5 screens. `fileprivate` (not
    /// `private`) so `StockResultsView` below, which owns the actual row list, can share it.
    fileprivate enum ActiveSheet: Identifiable {
        case itemDetail(Item)
        case countSession

        var id: String {
            switch self {
            case .itemDetail(let item): return "itemDetail-\(item.id)"
            case .countSession: return "countSession"
            }
        }
    }

    @Query(StockListView.allItemsDescriptor) private var allItems: [Item]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var expiringOnly = false
    @State private var activeSheet: ActiveSheet?

    /// Prefetches `lots` for the whole catalog in one round trip, since `expiringSoonCount` below
    /// (and every row's badge) reads `.lots` per item — avoids lazily faulting each item's lots
    /// one at a time.
    private static var allItemsDescriptor: FetchDescriptor<Item> {
        var descriptor = FetchDescriptor<Item>()
        descriptor.relationshipKeyPathsForPrefetching = [\.lots]
        return descriptor
    }

    private var expiringSoonCount: Int {
        allItems.filter { item in item.sortedLots.contains { $0.isExpiringSoon } }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: "In the pantry", title: "Stock") {
                SecondaryButton(title: "Count") { activeSheet = .countSession }
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

            // Search text (already debounced below) drives StockResultsView's own @Query, scoped
            // to a name/barcode predicate once it's long enough to be selective — the "unfiltered
            // @Query" half of the architecture review's finding. See that view's doc comment for
            // why the no-search case still has to fetch the whole catalog.
            StockResultsView(searchText: debouncedSearchText, expiringOnly: expiringOnly, activeSheet: $activeSheet)
        }
        .background(Color.larderBackground.ignoresSafeArea())
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .itemDetail(let item):
                NavigationStack { ItemDetailView(item: item) }
            case .countSession:
                CountSessionView()
            }
        }
        .task(id: searchText) {
            // Debounce: at catalog scale, reconstructing StockResultsView's @Query (and its
            // Swift-side sort) on every keystroke is real, avoidable work. `.task(id:)` cancels
            // the previous sleep automatically when `searchText` changes again before it elapses,
            // so only a pause in typing actually commits a new search.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
    }
}

/// Renders the filtered/sorted stock list. See `StockListView` for why `searchText` here is
/// already debounced and how it scopes this view's own `@Query`.
///
/// The base (no-search) case still fetches every item: sorting by soonest-expiry means reading
/// `earliestBestBefore`, a value computed from the `lots` relationship rather than a stored
/// attribute, so SwiftData can't express that ordering as a `SortDescriptor` — every item has to
/// be inspected in Swift regardless of query scope. Once there's enough search text to be
/// selective, though, narrowing the *fetch* to matching items first (rather than fetching
/// everything and filtering in Swift) means the expensive per-item relationship read only happens
/// for items that could actually be shown.
private struct StockResultsView: View {
    @Query private var items: [Item]
    let expiringOnly: Bool
    @Binding var activeSheet: StockListView.ActiveSheet?

    init(searchText: String, expiringOnly: Bool, activeSheet: Binding<StockListView.ActiveSheet?>) {
        self.expiringOnly = expiringOnly
        self._activeSheet = activeSheet

        var descriptor: FetchDescriptor<Item>
        if searchText.count >= 2 {
            descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { item in
                item.name.localizedStandardContains(searchText) || (item.barcode?.localizedStandardContains(searchText) ?? false)
            })
        } else {
            descriptor = FetchDescriptor<Item>()
        }
        descriptor.relationshipKeyPathsForPrefetching = [\.lots]
        _items = Query(descriptor)
    }

    private var visibleItems: [Item] {
        var result = items
        if expiringOnly {
            result = result.filter { item in item.sortedLots.contains { $0.isExpiringSoon } }
        }
        return result.sorted { lhs, rhs in
            switch (lhs.earliestBestBefore, rhs.earliestBestBefore) {
            case let (l?, r?): return l < r
            case (nil, nil): return lhs.name < rhs.name
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    var body: some View {
        if visibleItems.isEmpty {
            Spacer()
            Text("No items match.")
                .foregroundStyle(Color.larderSecondaryText)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleItems) { item in
                        Button {
                            activeSheet = .itemDetail(item)
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
                        ExpiryBadge(date: earliest)
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
