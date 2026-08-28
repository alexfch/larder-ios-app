import SwiftUI
import SwiftData

/// FR-5.2/FR-6.1: on-hand total, earliest best-before, every batch, and full swipeable history.
struct ItemDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss

    /// Single source of truth for "what's on screen right now," replacing three independent
    /// `@State` booleans/optionals each backing its own `.sheet()` modifier — the structural
    /// pattern the architecture review flagged as repeated across 5 screens. See `CheckInHubView`
    /// for where mutating two of those in the same closure actually caused a bug.
    private enum ActiveSheet: Identifiable {
        case checkOut
        case checkIn
        case editTransaction(Transaction)

        var id: String {
            switch self {
            case .checkOut: return "checkOut"
            case .checkIn: return "checkIn"
            case .editTransaction(let transaction): return "edit-\(transaction.id)"
            }
        }
    }

    let item: Item

    @State private var activeSheet: ActiveSheet?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(LarderFont.screenTitle())
                    Text("\(item.barcode ?? "no barcode") · counted in \(item.kind == .unit ? (item.noun ?? "unit") : (item.unit ?? "g"))")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.larderSecondaryText)
                }
                Spacer()
                ItemThumbnail(photoData: item.photoData, monogram: item.monogram, size: 72)
            }
            .padding(20)

            HStack(spacing: 0) {
                statBlock(value: item.formattedQuantity(item.onHandTotal), label: "On Hand")
                Divider().frame(height: 60).overlay(Color.larderDivider)
                if let earliest = item.earliestBestBefore {
                    statBlock(value: "\(earliest.formatted(.iso8601.year().month().day())) (\(earliest.relativeDayLabel))", label: "Earliest Best Before")
                } else {
                    statBlock(value: "—", label: "Earliest Best Before")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider().overlay(Color.larderDivider)

            List {
                Section {
                    if item.sortedLots.isEmpty {
                        Text("Nothing on the shelf. Check some in.")
                            .foregroundStyle(Color.larderSecondaryText)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(item.sortedLots) { lot in
                            HStack {
                                Text(item.formattedQuantity(lot.qty))
                                    .font(LarderFont.rowTitle())
                                Spacer()
                                Text(lot.exp.formatted(.iso8601.year().month().day()))
                                Text(lot.exp.relativeDayLabel)
                                    .foregroundStyle(Color.larderSecondaryText)
                            }
                            .font(.system(size: 15))
                        }
                    }
                } header: {
                    Text("Batches on the shelf")
                }

                Section {
                    if item.sortedTransactions.isEmpty {
                        Text("No movements yet.")
                            .foregroundStyle(Color.larderSecondaryText)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(item.sortedTransactions) { transaction in
                            HistoryRow(transaction: transaction)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        removeTransaction(transaction)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                    Button {
                                        activeSheet = .editTransaction(transaction)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }
                } header: {
                    HStack {
                        Text("History")
                        Spacer()
                        Text("swipe a row left")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.larderSecondaryText)
                    }
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    PrimaryButton(title: "Check Out") { activeSheet = .checkOut }
                    SecondaryButton(title: "Check In") { activeSheet = .checkIn }
                }
                .padding(20)
                .background(Color.larderBackground)
            }
        }
        .background(Color.larderBackground.ignoresSafeArea())
        .overlay(ToastOverlay(message: toastCenter.message))
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .checkOut:
                QuantitySheetView(item: item, mode: .checkOut, preselectedLot: item.sortedLots.first)
            case .checkIn:
                QuantitySheetView(item: item, mode: .checkIn)
            case .editTransaction(let transaction):
                EditTransactionSheet(item: item, transaction: transaction)
            }
        }
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
            Text(label)
                .trackedUppercase()
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.larderSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func removeTransaction(_ transaction: Transaction) {
        do {
            try StockService.remove(transaction, context: context)
            toastCenter.show("Movement removed — balance rolled back")
        } catch {
            toastCenter.show(error.localizedDescription)
        }
    }
}

struct HistoryRow: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(transaction.occurredAt.formatted(.iso8601.year().month().day())) · \(transaction.occurredAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.larderSecondaryText)
                Text("best before \(transaction.exp.formatted(.iso8601.year().month().day()))")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.larderSecondaryText)
            }
            Spacer()
            Text(transaction.action.rawValue)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.larderSecondaryText)
            Text(signedQuantity)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(transaction.action == .checkOut ? Color.larderInk : Color.larderAccent)
                .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var signedQuantity: String {
        let magnitude = transaction.item?.formattedQuantity(abs(transaction.qty)) ?? "\(abs(transaction.qty))"
        let isNegative = transaction.action == .checkOut || (transaction.action == .adjust && transaction.qty < 0)
        return (isNegative ? "−" : "+") + magnitude
    }
}
