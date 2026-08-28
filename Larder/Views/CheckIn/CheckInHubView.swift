import SwiftUI
import SwiftData

/// F2/F4: lists the 5 most recent check-in movements, newest first.
struct CheckInHubView: View {
    /// Single source of truth for "what's on screen right now," replacing what used to be six
    /// independent `@State` booleans/optionals each backing its own `.sheet()` modifier. This is
    /// the screen where the barcode-prefill bug was first observed: dismissing the scanner sheet
    /// and presenting the New Product sheet were two separate state mutations in the same
    /// synchronous closure, racing against SwiftUI's own presentation timing and against
    /// `NewProductFormView`'s old `.onAppear`-based prop capture. Reassigning one `Identifiable?`
    /// bound to one `.sheet(item:)` makes "switch to a different sheet" a single atomic transition.
    private enum ActiveSheet: Identifiable {
        case itemDetail(Item)
        case quantity(Item)
        case scanner
        case manualPick
        case newProduct(barcode: String?, name: String)

        var id: String {
            switch self {
            case .itemDetail(let item): return "itemDetail-\(item.id)"
            case .quantity(let item): return "quantity-\(item.id)"
            case .scanner: return "scanner"
            case .manualPick: return "manualPick"
            case .newProduct(let barcode, let name): return "newProduct-\(barcode ?? "")-\(name)"
            }
        }
    }

    @Query(sort: \Transaction.occurredAt, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Item.name) private var allItems: [Item]

    @State private var activeSheet: ActiveSheet?

    private var recentCheckIns: [Transaction] {
        allTransactions.filter { $0.action == .checkIn }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: "Pantry · \(todayEyebrowDate())",
                title: "Check In",
                subtitle: "Scan the barcode, or add it by hand if the pack has none."
            )

            Divider().overlay(Color.larderDivider)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recently checked in")
                        .trackedUppercase()
                        .font(LarderFont.eyebrow())
                        .foregroundStyle(Color.larderSecondaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)

                    if recentCheckIns.isEmpty {
                        Text("Nothing checked in yet.")
                            .foregroundStyle(Color.larderSecondaryText)
                            .padding(20)
                    } else {
                        ForEach(recentCheckIns) { transaction in
                            Button {
                                if let item = transaction.item {
                                    activeSheet = .itemDetail(item)
                                }
                            } label: {
                                RecentCheckInRow(transaction: transaction)
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
            case .itemDetail(let item):
                NavigationStack { ItemDetailView(item: item) }
            case .quantity(let item):
                QuantitySheetView(item: item, mode: .checkIn)
            case .manualPick:
                ManualPickListView(mode: .checkIn) { item in
                    activeSheet = .quantity(item)
                } onAddNewProduct: { typedName in
                    activeSheet = .newProduct(barcode: nil, name: typedName)
                }
            case .scanner:
                BarcodeScannerView { code in
                    if let match = allItems.first(where: { $0.barcode == code }) {
                        activeSheet = .quantity(match)
                    } else {
                        activeSheet = .newProduct(barcode: code, name: "")
                    }
                }
            case .newProduct(let barcode, let name):
                NewProductFormView(prefilledBarcode: barcode, prefilledName: name)
            }
        }
    }
}

struct RecentCheckInRow: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.item?.name ?? "Deleted item")
                    .font(LarderFont.rowTitle())
                Text("\(transaction.occurredAt.formatted(.iso8601.year().month().day())) · \(transaction.occurredAt.formatted(date: .omitted, time: .shortened)) · best before \(transaction.exp.formatted(.iso8601.year().month().day()))")
                    .font(LarderFont.rowSubtitle())
                    .foregroundStyle(Color.larderSecondaryText)
            }
            Spacer()
            Text("+\(transaction.item?.formattedQuantity(transaction.qty) ?? "")")
                .font(LarderFont.quantityValue())
                .foregroundStyle(Color.larderAccent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
