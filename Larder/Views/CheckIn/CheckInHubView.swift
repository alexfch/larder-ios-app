import SwiftUI

/// F2/F4: lists the 5 most recent check-in movements, newest first, until the user types into
/// the search field, at which point it switches to showing every catalog match -- replacing the
/// previous "Manual" button's detour through a separate `ManualPickListView` sheet with in-place
/// filtering, per the redesign. Every row -- recent or searched -- opens the Check In quantity
/// sheet directly (not Item Detail): this screen's job is fast re-check-in, not browsing.
struct CheckInHubView: View {
    /// Single source of truth for "what's on screen right now," replacing what used to be six
    /// independent `@State` booleans/optionals each backing its own `.sheet()` modifier. This is
    /// the screen where the barcode-prefill bug was first observed: dismissing the scanner sheet
    /// and presenting the New Product sheet were two separate state mutations in the same
    /// synchronous closure, racing against SwiftUI's own presentation timing and against
    /// `NewProductFormView`'s old `.onAppear`-based prop capture. Reassigning one `Identifiable?`
    /// bound to one `.sheet(item:)` makes "switch to a different sheet" a single atomic transition.
    private enum ActiveSheet: Identifiable {
        case quantity(Item)
        case scanner
        case settings
        case newProduct(barcode: String?, name: String)

        var id: String {
            switch self {
            case .quantity(let item): return "quantity-\(item.id)"
            case .scanner: return "scanner"
            case .settings: return "settings"
            case .newProduct(let barcode, let name): return "newProduct-\(barcode ?? "")-\(name)"
            }
        }
    }

    @Environment(CatalogStore.self) private var store

    @State private var activeSheet: ActiveSheet?
    @State private var searchText = ""

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var recentCheckIns: [Transaction] {
        store.transactions
            .filter { $0.action == .checkIn }
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(5)
            .map { $0 }
    }

    private var searchMatches: [Item]? {
        guard !trimmedSearch.isEmpty else { return nil }
        return store.items
            .filter { $0.name.lowercased().contains(trimmedSearch) || ($0.barcode ?? "").contains(trimmedSearch) }
            .sorted { $0.name < $1.name }
    }

    private var listLabel: String {
        guard let searchMatches else { return "Recently checked in" }
        return "\(searchMatches.count) \(searchMatches.count == 1 ? "match" : "matches")"
    }

    private var listHint: String {
        searchMatches == nil ? "Newest first" : "Tap to check in"
    }

    private func openQuantity(for itemId: String) {
        guard let item = store.item(id: itemId) else { return }
        activeSheet = .quantity(item)
    }

    var body: some View {
        VStack(spacing: 0) {
            LarderTopBar { activeSheet = .settings }

            Text("Check in")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(Color.larderInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().overlay(Color.larderDivider)

            HStack {
                Text(listLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.larderInk)
                Spacer()
                Text(listHint)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.larderSecondaryText)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.larderSoft)

            Divider().overlay(Color.larderDivider)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let searchMatches {
                        if searchMatches.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No product matches \u{201C}\(searchText)\u{201D}.")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.larderInk)
                                Text("Add it with New, or scan its barcode.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.larderSecondaryText)
                            }
                            .padding(18)
                        } else {
                            ForEach(searchMatches) { item in
                                let total = CatalogDerivation.onHandTotal(itemId: item.id, transactions: store.transactions)
                                Button {
                                    openQuantity(for: item.id)
                                } label: {
                                    HubRow(
                                        item: item,
                                        transactions: store.transactions,
                                        overrideMeta: total > 0
                                            ? "on hand · bb \(CatalogDerivation.earliestBestBefore(itemId: item.id, transactions: store.transactions).formattedExpirationDate)"
                                            : "nothing on hand"
                                    )
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(Color.larderDivider)
                            }
                        }
                    } else if recentCheckIns.isEmpty {
                        Text("Nothing checked in yet.")
                            .foregroundStyle(Color.larderSecondaryText)
                            .padding(20)
                    } else {
                        ForEach(recentCheckIns) { transaction in
                            if let item = store.item(id: transaction.itemId) {
                                Button {
                                    openQuantity(for: item.id)
                                } label: {
                                    HubRow(
                                        item: item,
                                        transactions: store.transactions,
                                        overrideValue: "+\(Int(transaction.qty.rounded()))",
                                        overrideUnit: item.quantityUnitSuffix(for: transaction.qty),
                                        overrideMeta: "\(transaction.occurredAt.formatted(.iso8601.year().month().day())) · bb \(transaction.exp.formattedExpirationDate)",
                                        isHighlighted: true
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                DeletedTransactionRow(transaction: transaction)
                            }
                            Divider().overlay(Color.larderDivider)
                        }
                    }
                }
            }

            VStack(spacing: 10) {
                InlineSearchField(text: $searchText, placeholder: "Find a product to check in")
                HStack(spacing: 8) {
                    InlineIconButton(title: "Scan", systemIcon: "barcode.viewfinder") {
                        activeSheet = .scanner
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(2)
                    InlineIconButton(title: "New", systemIcon: "plus", isOutlined: true) {
                        activeSheet = .newProduct(barcode: nil, name: "")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .background(Color.larderBackground.ignoresSafeArea())
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .quantity(let item):
                QuantitySheetView(item: item, mode: .checkIn)
            case .scanner:
                BarcodeScannerView { code in
                    if let match = store.item(matchingBarcode: code) {
                        activeSheet = .quantity(match)
                    } else {
                        activeSheet = .newProduct(barcode: code, name: "")
                    }
                }
            case .newProduct(let barcode, let name):
                // Reassigning `activeSheet` to `.quantity(item)` here -- rather than having
                // `NewProductFormView` present or dismiss anything itself -- is the same atomic
                // single-sheet transition described on `ActiveSheet` above: the New Product
                // sheet is replaced by the Check In sheet for the item that was just created.
                NewProductFormView(prefilledBarcode: barcode, prefilledName: name) { item in
                    activeSheet = .quantity(item)
                }
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
    }
}

/// A recent check-in whose item has since been deleted -- can't be re-checked-in (there's nothing
/// to open), so this renders the same information without the tap action `HubRow` normally has.
private struct DeletedTransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Deleted item")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.larderInk)
                Text("\(transaction.occurredAt.formatted(.iso8601.year().month().day())) · bb \(transaction.exp.formattedExpirationDate)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.larderSecondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
