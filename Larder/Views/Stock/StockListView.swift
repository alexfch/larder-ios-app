import SwiftUI
import UniformTypeIdentifiers

/// FR-5.1: every item, sorted soonest-expiring first (no-batch items last), with search and
/// filter chips (All / Expiring soon / Multi-batch / Opened). Hosts the entry point into a
/// stock-take (FR-7.1).
struct StockListView: View {
    /// Single source of truth for "what's on screen right now," replacing two independent
    /// `@State` optionals/booleans each backing its own `.sheet()` modifier — the structural
    /// pattern the architecture review flagged as repeated across 5 screens.
    private enum ActiveSheet: Identifiable {
        case itemDetail(Item)
        case countSession
        case settings

        var id: String {
            switch self {
            case .itemDetail(let item): return "itemDetail-\(item.id)"
            case .countSession: return "countSession"
            case .settings: return "settings"
            }
        }
    }

    /// Chips replacing the previous single "Expiring ≤ 14 days" toggle. `.batches`/`.opened`
    /// filter locally (below) rather than extending `CatalogFiltering.stockVisibleItems`, since
    /// no other caller needs them yet and this keeps that shared function's contract unchanged.
    private enum StockFilter {
        case all, expiring, batches, opened
    }

    @Environment(CatalogStore.self) private var store
    @Environment(ToastCenter.self) private var toastCenter

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var filter: StockFilter = .all
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
        var result = CatalogFiltering.stockVisibleItems(items, transactions: store.transactions, expiringOnly: filter == .expiring)
        switch filter {
        case .batches:
            result = result.filter { CatalogDerivation.lots(itemId: $0.id, transactions: store.transactions).count > 1 }
        case .opened:
            result = result.filter { item in
                CatalogDerivation.lots(itemId: item.id, transactions: store.transactions)
                    .contains { (item.packageOpenStatus(for: $0.qty)?.openedAmount ?? 0) > 0 }
            }
        case .all, .expiring:
            break
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            LarderTopBar { activeSheet = .settings }

            HStack {
                Text("Stock")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Color.larderInk)
                Spacer()
                Menu {
                    Button("Export Backup") { exportBackup() }
                    Button("Import Backup…") { isImportingBackup = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.larderSecondaryText)
                }
                Button {
                    activeSheet = .countSession
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.rectangle")
                            .font(.system(size: 13, weight: .medium))
                        Text("Count")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.larderAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                }
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.larderAccent, lineWidth: 2))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.larderSecondaryText)
                TextField("Search name or barcode", text: $searchText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.larderInk)
                    .padding(.vertical, 6)
            }
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.larderEdge).frame(height: 1)
            }
            .padding(.horizontal, 18)

            Divider().overlay(Color.larderDivider)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All · \(store.items.count)", isOn: filter == .all) { filter = .all }
                    filterChip("Expiring soon · \(expiringSoonCount)", isOn: filter == .expiring) { filter = .expiring }
                    filterChip("Multi-batch", isOn: filter == .batches) { filter = .batches }
                    filterChip("Opened", isOn: filter == .opened) { filter = .opened }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }

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
                        Text("\(visibleItems.count) of \(store.items.count) products shown")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.larderFaint)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 20)
                    }
                }
            }
        }
        .background(Color.larderBackground.ignoresSafeArea())
        .simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        )
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .itemDetail(let item):
                NavigationStack { ItemDetailView(item: item) }
            case .countSession:
                CountSessionView()
            case .settings:
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { activeSheet = nil }
                            }
                        }
                }
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

    private func filterChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isOn ? Color.larderOnAccent : Color.larderInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isOn ? Color.larderAccent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isOn ? Color.larderAccent : Color.larderEdge, lineWidth: 1))
        }
        .buttonStyle(.plain)
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

    private var total: Double {
        lots.reduce(0) { $0 + $1.qty }
    }

    private var earliest: Date? {
        lots.compactMap(\.exp).min()
    }

    private var isUrgent: Bool {
        earliest.map { $0.daysFromToday <= 14 } ?? false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(isUrgent ? Color.larderWarn : Color.clear)
                .frame(width: 3)

            ItemThumbnail(
                photoData: nil,
                photoStorageRef: item.photoStorageRef,
                monogram: item.monogram,
                size: 52,
                monogramBackground: Color.larderMonoTones[item.monogramToneIndex]
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 12)
            .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.larderInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(quantityParts.value)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(Color.larderInk)
                    Text(quantityParts.unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.larderSecondaryText)
                }
                Text(earliest.map { "\($0.formatted(.iso8601.year().month().day())) · \($0.relativeDayLabel)" } ?? "no best-before date")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isUrgent ? Color.larderWarn : Color.larderSecondaryText)

                if lots.count > 1 {
                    HStack(spacing: 3) {
                        ForEach(Array(lots.enumerated()), id: \.element.id) { index, lot in
                            let lotUrgent = (lot.exp?.daysFromToday ?? .max) <= 14
                            RoundedRectangle(cornerRadius: 2)
                                .fill(lotUrgent ? Color.larderWarn : (index == 0 ? Color.larderAccent : Color.larderEdge))
                                .frame(width: max(lot.qty / max(total, 1), 0.06) * 100, height: 4)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 12)
            .padding(.trailing, 18)
            .padding(.leading, 12)
        }
    }

    /// `onHandTotal` sums the derived lots and `formattedQuantity` re-derives a string from it —
    /// real work, done once here per row rather than twice (value + unit) via two separate calls.
    private var quantityParts: (value: String, unit: String) {
        let full = item.formattedQuantity(total)
        let parts = full.components(separatedBy: " ")
        let value = parts.first ?? full
        let unit = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
        return (value, unit)
    }
}
