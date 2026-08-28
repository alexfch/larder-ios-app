import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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

    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toastCenter
    @Query(StockListView.allItemsDescriptor) private var allItems: [Item]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var expiringOnly = false
    @State private var activeSheet: ActiveSheet?

    @State private var exportDocument: BackupDocument?
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var backupErrorMessage: String?

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
                HStack(spacing: 12) {
                    Menu {
                        Button("Export Backup") { exportBackup() }
                        Button("Import Backup…") { isImportingBackup = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.larderInk)
                    }
                    SecondaryButton(title: "Count") { activeSheet = .countSession }
                        .frame(width: 96)
                }
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
        .fileExporter(
            isPresented: $isExportingBackup,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Larder Backup \(backupFilenameDate())"
        ) { result in
            switch result {
            case .success:
                toastCenter.show("Backup exported")
            case .failure(let error):
                backupErrorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isImportingBackup, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importBackup(from: url)
            case .failure(let error):
                backupErrorMessage = error.localizedDescription
            }
        }
        .alert("Backup", isPresented: Binding(
            get: { backupErrorMessage != nil },
            set: { isPresented in if !isPresented { backupErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupErrorMessage ?? "")
        }
    }

    private func exportBackup() {
        do {
            exportDocument = BackupDocument(data: try BackupService.export(context: context))
            isExportingBackup = true
        } catch {
            backupErrorMessage = error.localizedDescription
        }
    }

    private func importBackup(from url: URL) {
        // Files handed back by `.fileImporter` are security-scoped: reading them requires
        // explicitly starting (and, once done, stopping) access.
        guard url.startAccessingSecurityScopedResource() else {
            backupErrorMessage = "Couldn't access that file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let summary = try BackupService.importBackup(data, context: context)
            if summary.imported == 0 {
                toastCenter.show("Nothing new to import — already up to date")
            } else {
                toastCenter.show("Imported \(summary.imported) item(s)")
            }
        } catch {
            backupErrorMessage = error.localizedDescription
        }
    }

    private func backupFilenameDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
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
        CatalogFiltering.stockVisibleItems(items, expiringOnly: expiringOnly)
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
                Text(quantityParts.value)
                    .font(LarderFont.quantityValue())
                Text(quantityParts.unit)
                    .font(LarderFont.quantityUnit())
                    .foregroundStyle(Color.larderSecondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// `onHandTotal` sums the `lots` relationship and `formattedQuantity` re-derives a string
    /// from it — real work, previously done twice per row (once for the value, once for the
    /// unit) by two separate methods that each called `item.formattedQuantity(item.onHandTotal)`
    /// independently. Splitting once here, within a single `body` evaluation, halves that work
    /// with no correctness risk, unlike caching across renders on the model itself (see
    /// `Item.swift`'s doc comment on why that's deliberately not done).
    private var quantityParts: (value: String, unit: String) {
        let full = item.formattedQuantity(item.onHandTotal)
        let parts = full.components(separatedBy: " ")
        let value = parts.first ?? full
        let unit = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
        return (value, unit)
    }
}
