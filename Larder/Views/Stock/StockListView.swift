import SwiftUI
import UniformTypeIdentifiers

/// FR-5.1: every item, sorted soonest-expiring first (no-batch items last), with search and
/// an "Expiring ≤ 14 days" filter. Hosts the entry point into a stock-take (FR-7.1).
struct StockListView: View {
    /// Single source of truth for "what's on screen right now," replacing two independent
    /// `@State` optionals/booleans each backing its own `.sheet()` modifier — the structural
    /// pattern the architecture review flagged as repeated across 5 screens.
    private enum ActiveSheet: Identifiable {
        case itemDetail(Item)
        case countSession

        var id: String {
            switch self {
            case .itemDetail(let item): return "itemDetail-\(item.id)"
            case .countSession: return "countSession"
            }
        }
    }

    @Environment(CatalogStore.self) private var store
    @Environment(ToastCenter.self) private var toastCenter

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var expiringOnly = false
    @State private var activeSheet: ActiveSheet?

    @State private var exportDocument: BackupDocument?
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var backupErrorMessage: String?

    /// Uses the same batch-precomputed summary `CatalogFiltering.stockVisibleItems` uses below,
    /// rather than re-deriving lots per item, for the same reason: at catalog scale that added up
    /// to a measurable, avoidable cost (see `CatalogDerivation.lotsByItem`'s doc comment).
    private var expiringSoonCount: Int {
        let summaries = CatalogDerivation.lotsByItem(transactions: store.transactions)
        return store.items.filter { summaries[$0.id]?.isExpiringSoon ?? false }.count
    }

    /// The whole (5,000-item-capped) catalog is already synced locally via `CatalogStore`
    /// (ADR-0003), so this filters/sorts client-side rather than scoping a fetch predicate the
    /// way the old `@Query`-based version did.
    private var visibleItems: [Item] {
        var items = store.items
        if debouncedSearchText.count >= 2 {
            items = items.filter {
                $0.name.localizedStandardContains(debouncedSearchText)
                    || ($0.barcode?.localizedStandardContains(debouncedSearchText) ?? false)
            }
        }
        return CatalogFiltering.stockVisibleItems(items, transactions: store.transactions, expiringOnly: expiringOnly)
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
                                StockRow(item: item, transactions: store.transactions)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Color.larderDivider)
                        }
                    }
                }
            }
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
            // Debounce: at catalog scale, re-filtering on every keystroke is real, avoidable
            // work. `.task(id:)` cancels the previous sleep automatically when `searchText`
            // changes again before it elapses, so only a pause in typing actually commits a new
            // search.
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
            exportDocument = BackupDocument(data: try BackupService.export(store: store))
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
            let summary = try BackupService.importBackup(data, store: store)
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

struct StockRow: View {
    let item: Item
    let transactions: [Transaction]

    private var lots: [Lot] {
        CatalogDerivation.sortedLots(itemId: item.id, transactions: transactions)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Photos aren't synced to Cloud Storage yet (see NewProductFormView), so this is
            // always the monogram fallback for now.
            ItemThumbnail(photoData: nil, monogram: item.monogram)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(LarderFont.rowTitle())
                Text(item.barcode ?? "no barcode")
                    .font(LarderFont.rowSubtitle())
                    .foregroundStyle(Color.larderSecondaryText)
                HStack(spacing: 8) {
                    if let earliest = lots.map(\.exp).min() {
                        ExpiryBadge(date: earliest)
                    }
                    if lots.count > 1 {
                        OutlineTag(text: "\(lots.count) batches")
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

    /// `onHandTotal` sums the derived lots and `formattedQuantity` re-derives a string from it —
    /// real work, done once here per row rather than twice (value + unit) via two separate calls.
    private var quantityParts: (value: String, unit: String) {
        let total = lots.reduce(0) { $0 + $1.qty }
        let full = item.formattedQuantity(total)
        let parts = full.components(separatedBy: " ")
        let value = parts.first ?? full
        let unit = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
        return (value, unit)
    }
}
