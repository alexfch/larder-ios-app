import SwiftUI

/// FR-5.2/FR-6.1: on-hand total, earliest best-before, every batch, and full swipeable history.
struct ItemDetailView: View {
    @Environment(CatalogStore.self) private var store
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
    /// The screen this detail view was opened from, shown next to the back chevron -- the design
    /// tracks this as in-app navigation state; here it's just the caller's name, since every
    /// entry point presents this as a sheet.
    var backLabel: String = "Stock"

    @State private var activeSheet: ActiveSheet?

    private var sortedLots: [Lot] {
        CatalogDerivation.sortedLots(itemId: item.id, transactions: store.transactions)
    }

    private var sortedTransactions: [Transaction] {
        CatalogDerivation.sortedTransactions(itemId: item.id, transactions: store.transactions)
    }

    private var onHandTotal: Double {
        sortedLots.reduce(0) { $0 + $1.qty }
    }

    private var earliest: Date? {
        sortedLots.compactMap(\.exp).min()
    }

    private var isUrgent: Bool {
        earliest.map { $0.daysFromToday <= 14 } ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text(backLabel)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(Color.larderSecondaryText)
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.name)
                            .font(.system(size: 27, weight: .heavy))
                            .foregroundStyle(Color.larderInk)
                        Text("\(item.barcode ?? "no barcode") · counted in \(item.quantityUnitSuffix(for: 1))")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.larderSecondaryText)
                    }
                    Spacer(minLength: 8)
                    ItemThumbnail(
                        photoData: nil,
                        photoStorageRef: item.photoStorageRef,
                        monogram: item.monogram,
                        size: 58,
                        monogramBackground: Color.larderMonoTones[item.monogramToneIndex]
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            HStack(spacing: 0) {
                statBlock(value: item.formattedQuantity(onHandTotal), label: "On hand")
                Divider().frame(height: 44).overlay(Color.larderDivider)
                statBlock(
                    value: earliestBestBeforeText,
                    label: "Earliest best before",
                    valueColor: isUrgent ? Color.larderWarn : Color.larderInk
                )
                .padding(.leading, 14)
            }
            .padding(.horizontal, 18)
            .overlay(alignment: .top) { Rectangle().fill(Color.larderDivider).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.larderDivider).frame(height: 1) }

            List {
                Section {
                    if sortedLots.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Nothing on the shelf.")
                                .font(.system(size: 15, weight: .bold))
                            Text("This product is in the catalog but has no stock. Check a batch in and it will appear here, oldest first.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.larderInk2)
                            Button {
                                activeSheet = .checkIn
                            } label: {
                                HStack(spacing: 10) {
                                    Text("Check some in")
                                        .font(.system(size: 12, weight: .semibold))
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(Color.larderInk)
                                .padding(.horizontal, 14)
                                .frame(height: 44)
                            }
                            .overlay(Rectangle().strokeBorder(Color.larderEdge, lineWidth: 1))
                        }
                        .padding(16)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.larderEdge, style: StrokeStyle(lineWidth: 1, dash: [4])))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    } else {
                        ForEach(Array(sortedLots.enumerated()), id: \.element.id) { index, lot in
                            lotRow(lot, index: index)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        }
                    }
                } header: {
                    HStack {
                        Text("Batches on the shelf")
                        Spacer()
                        Text(sortedLots.isEmpty ? "Empty" : "Draw from top")
                            .foregroundStyle(Color.larderSecondaryText)
                    }
                }

                Section {
                    if sortedTransactions.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("No movements yet.")
                                .font(.system(size: 14, weight: .bold))
                            Text("Every check-in and check-out lands here as a dated line you can correct later.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.larderInk2)
                            VStack(alignment: .leading, spacing: 9) {
                                Text("How this product is tracked")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Color.larderSecondaryText)
                                ForEach(trackingFacts, id: \.key) { fact in
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(fact.key)
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(Color.larderSecondaryText)
                                            .frame(width: 96, alignment: .leading)
                                        Text(fact.value)
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                }
                            }
                            .padding(.top, 14)
                            .overlay(alignment: .top) { Rectangle().fill(Color.larderDivider).frame(height: 1) }
                        }
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(sortedTransactions) { transaction in
                            HistoryRow(transaction: transaction, item: item)
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
                        Text("Movement history")
                        Spacer()
                        Text(sortedTransactions.isEmpty ? "Nothing logged" : "Tap to correct")
                            .foregroundStyle(Color.larderSecondaryText)
                    }
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    InlineIconButton(title: "Check out", systemIcon: "arrow.up") {
                        activeSheet = .checkOut
                    }
                    InlineIconButton(title: "Check in", systemIcon: "arrow.down", isOutlined: true) {
                        activeSheet = .checkIn
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .background(Color.larderBackground)
            }
        }
        .background(Color.larderBackground.ignoresSafeArea())
        .overlay(ToastOverlay(message: toastCenter.message))
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .checkOut:
                QuantitySheetView(item: item, mode: .checkOut, preselectedLot: sortedLots.first)
            case .checkIn:
                QuantitySheetView(item: item, mode: .checkIn)
            case .editTransaction(let transaction):
                EditTransactionSheet(item: item, transaction: transaction)
            }
        }
    }

    private var earliestBestBeforeText: String {
        if let earliest {
            return "\(earliest.formatted(.iso8601.year().month().day())) (\(earliest.relativeDayLabel))"
        }
        return sortedLots.isEmpty ? "—" : "No expiration date"
    }

    private var trackingFacts: [(key: String, value: String)] {
        [
            ("Counted as", item.isCountedInWholeUnits ? "Whole units · \(item.quantityUnitSuffix(for: 1))" : "Weight / volume in \(item.quantityUnitSuffix(for: 0))"),
            ("Barcode", item.barcode ?? "None on file"),
            ("Expiry", item.noExpirationDate ? "No expiration date tracked" : "Dated per batch on check-in"),
        ]
    }

    private func statBlock(value: String, label: String, valueColor: Color = .larderInk) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.larderSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private func lotRow(_ lot: Lot, index: Int) -> some View {
        let urgent = (lot.exp?.daysFromToday ?? .max) <= 14
        let barColor = urgent ? Color.larderWarn : (index == 0 ? Color.larderAccent : Color.larderEdge)
        return HStack(spacing: 0) {
            Rectangle().fill(barColor).frame(width: 3).frame(maxHeight: .infinity)
            VStack {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(barColor)
            }
            .frame(width: 44)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) { Rectangle().fill(Color.larderDivider).frame(width: 1) }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.packageOpenStatusText(for: lot.qty) ?? item.formattedQuantity(lot.qty))
                    .font(.system(size: 16, weight: .bold))
                Text(lot.exp.formattedExpirationDate + (lot.exp.map { " · \($0.relativeDayLabel)" } ?? ""))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.larderSecondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Spacer(minLength: 0)

            if index == 0 {
                Text("Use first")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(barColor)
                    .padding(.trailing, 12)
            }
        }
        .background(index == 0 ? Color.larderSurface : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.larderDivider, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func removeTransaction(_ transaction: Transaction) {
        do {
            try StockService.remove(transaction, store: store)
            toastCenter.show("Movement removed — balance rolled back")
        } catch {
            toastCenter.show(error.localizedDescription)
        }
    }
}

struct HistoryRow: View {
    let transaction: Transaction
    let item: Item?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(actionLabel)
                    .trackedUppercase()
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.larderInk)
                Text("\(transaction.occurredAt.formatted(.iso8601.year().month().day())) \(transaction.occurredAt.formatted(date: .omitted, time: .shortened)) · bb \(transaction.exp.formattedExpirationDate)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.larderSecondaryText)
            }
            Spacer()
            Text(signedQuantity)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(transaction.action == .checkIn ? Color.larderAccent : Color.larderInk)
        }
        .padding(.vertical, 4)
    }

    private var actionLabel: String {
        switch transaction.action {
        case .checkIn: return "Checked in"
        case .checkOut: return "Checked out"
        case .adjust: return "Adjusted"
        }
    }

    private var signedQuantity: String {
        let magnitude = item?.formattedQuantity(abs(transaction.qty)) ?? "\(abs(transaction.qty))"
        let isNegative = transaction.action == .checkOut || (transaction.action == .adjust && transaction.qty < 0)
        return (isNegative ? "−" : "+") + magnitude
    }
}
