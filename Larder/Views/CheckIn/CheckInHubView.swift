import SwiftUI
import SwiftData

/// F2/F4: lists the 5 most recent check-in movements, newest first.
struct CheckInHubView: View {
    @Query(sort: \Transaction.occurredAt, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Item.name) private var allItems: [Item]

    @State private var selectedItemForDetail: Item?
    @State private var scanQuantityItem: Item?
    @State private var showScanner = false
    @State private var showManualPick = false
    @State private var newProductBarcode: String?
    @State private var newProductName: String = ""
    @State private var showNewProduct = false

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
                                selectedItemForDetail = transaction.item
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
                PrimaryButton(title: "Scan") { showScanner = true }
                SecondaryButton(title: "Manual") { showManualPick = true }
            }
            .padding(20)
        }
        .background(Color.larderBackground.ignoresSafeArea())
        .sheet(item: $selectedItemForDetail) { item in
            NavigationStack { ItemDetailView(item: item) }
        }
        .sheet(item: $scanQuantityItem) { item in
            QuantitySheetView(item: item, mode: .checkIn)
        }
        .sheet(isPresented: $showManualPick) {
            ManualPickListView(mode: .checkIn) { item in
                showManualPick = false
                scanQuantityItem = item
            } onAddNewProduct: { typedName in
                showManualPick = false
                newProductBarcode = nil
                newProductName = typedName
                showNewProduct = true
            }
        }
        .sheet(isPresented: $showScanner) {
            BarcodeScannerView { code in
                showScanner = false
                if let match = allItems.first(where: { $0.barcode == code }) {
                    scanQuantityItem = match
                } else {
                    newProductBarcode = code
                    newProductName = ""
                    showNewProduct = true
                }
            }
        }
        .sheet(isPresented: $showNewProduct) {
            NewProductFormView(prefilledBarcode: newProductBarcode, prefilledName: newProductName)
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
