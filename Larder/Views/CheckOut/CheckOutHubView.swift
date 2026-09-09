import SwiftUI

/// F1: opens by default. Shows the 5 items nearest their earliest best-before date until the
/// user types into the search field, at which point it switches to showing every in-stock match
/// -- replacing the previous "Manual" button's detour through a separate `ManualPickListView`
/// sheet with in-place filtering, per the redesign.
struct CheckOutHubView: View {
    /// Single source of truth for "what's on screen right now," replacing what used to be four
    /// independent `@State` booleans/optionals each backing its own `.sheet()` modifier. Mutating
    /// two of those in the same synchronous closure (dismiss one sheet, present another) raced
    /// against SwiftUI's own presentation/dismissal timing — the root cause of the barcode-prefill
    /// bug documented in the architecture review. Reassigning one `Identifiable?` bound to one
    /// `.sheet(item:)` makes "switch to a different sheet" a single atomic transition instead.
    private enum ActiveSheet: Identifiable {
        case quantity(Item)
        case scanner
        case settings

        var id: String {
            switch self {
            case .quantity(let item): return "quantity-\(item.id)"
            case .scanner: return "scanner"
            case .settings: return "settings"
            }
        }
    }

    @Environment(CatalogStore.self) private var store
    @Environment(ToastCenter.self) private var toastCenter

    @State private var activeSheet: ActiveSheet?
    @State private var searchText = ""

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var searchMatches: [Item]? {
        guard !trimmedSearch.isEmpty else { return nil }
        return CatalogFiltering.manualPickFilteredItems(store.items, transactions: store.transactions, mode: .checkOut)
            .filter { $0.name.lowercased().contains(trimmedSearch) || ($0.barcode ?? "").contains(trimmedSearch) }
            .sorted { $0.name < $1.name }
    }

    private var displayedItems: [Item] {
        searchMatches ?? CatalogFiltering.checkOutShortlist(store.items, transactions: store.transactions)
    }

    private var listLabel: String {
        guard let searchMatches else { return "Use first · oldest batch" }
        return "\(searchMatches.count) \(searchMatches.count == 1 ? "match" : "matches")"
    }

    var body: some View {
        VStack(spacing: 0) {
            LarderTopBar { activeSheet = .settings }

            Text("Check out")
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
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.larderSoft)

            Divider().overlay(Color.larderDivider)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if displayedItems.isEmpty {
                        if searchMatches != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Nothing on hand matches \u{201C}\(searchText)\u{201D}.")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.larderInk)
                                Text("Check the spelling, or scan the barcode instead.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.larderSecondaryText)
                            }
                            .padding(18)
                        } else {
                            Text("Nothing due out yet. Check something in first.")
                                .foregroundStyle(Color.larderSecondaryText)
                                .padding(20)
                        }
                    } else {
                        ForEach(displayedItems) { item in
                            Button {
                                activeSheet = .quantity(item)
                            } label: {
                                CheckOutRow(item: item, transactions: store.transactions)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Color.larderDivider)
                        }
                    }
                }
            }

            VStack(spacing: 10) {
                InlineSearchField(text: $searchText, placeholder: "Find a product to check out")
                InlineIconButton(title: "Scan a barcode", systemIcon: "barcode.viewfinder") {
                    activeSheet = .scanner
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
                QuantitySheetView(
                    item: item,
                    mode: .checkOut,
                    preselectedLot: CatalogDerivation.sortedLots(itemId: item.id, transactions: store.transactions).first
                )
            case .scanner:
                BarcodeScannerView { code in
                    if let match = store.item(matchingBarcode: code) {
                        activeSheet = .quantity(match)
                    } else {
                        // Unlike Check In, there's no "add new product" path on Check Out for an
                        // unrecognized scan — this used to be dead-end silence (the scan simply
                        // did nothing, with a `scannedUnmatchedItem` state var declared but never
                        // read or written). Surface it instead.
                        activeSheet = nil
                        toastCenter.show("No item on file for that barcode — check it in first.")
                    }
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
