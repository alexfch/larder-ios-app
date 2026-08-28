import SwiftUI
import SwiftData

/// F1: opens by default; lists the 5 items nearest their earliest best-before date.
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
        case manualPick

        var id: String {
            switch self {
            case .quantity(let item): return "quantity-\(item.id)"
            case .scanner: return "scanner"
            case .manualPick: return "manualPick"
            }
        }
    }

    @Environment(ToastCenter.self) private var toastCenter
    @Query(sort: \Item.name) private var allItems: [Item]

    @State private var activeSheet: ActiveSheet?

    private var shortlist: [Item] {
        allItems
            .filter { $0.onHandTotal > 0 && $0.earliestBestBefore != nil }
            .sorted { ($0.earliestBestBefore ?? .distantFuture) < ($1.earliestBestBefore ?? .distantFuture) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: "Pantry · \(todayEyebrowDate())",
                title: "Check Out",
                subtitle: "Scan what you are taking, or pick it from the list."
            )

            Divider().overlay(Color.larderDivider)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Use these first — earliest best before")
                        .trackedUppercase()
                        .font(LarderFont.eyebrow())
                        .foregroundStyle(Color.larderSecondaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)

                    if shortlist.isEmpty {
                        Text("Nothing due out yet. Check something in first.")
                            .foregroundStyle(Color.larderSecondaryText)
                            .padding(20)
                    } else {
                        ForEach(shortlist) { item in
                            Button {
                                activeSheet = .quantity(item)
                            } label: {
                                HubRow(item: item)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Color.larderDivider)
                        }
                    }
                }
            }

            VStack(spacing: 10) {
                PrimaryButton(title: "Scan") { activeSheet = .scanner }
                SecondaryButton(title: "Manual") { activeSheet = .manualPick }
            }
            .padding(20)
        }
        .background(Color.larderBackground.ignoresSafeArea())
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .quantity(let item):
                QuantitySheetView(item: item, mode: .checkOut, preselectedLot: item.sortedLots.first)
            case .manualPick:
                ManualPickListView(mode: .checkOut) { item in
                    activeSheet = .quantity(item)
                }
            case .scanner:
                BarcodeScannerView { code in
                    if let match = allItems.first(where: { $0.barcode == code }) {
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
            }
        }
    }
}
