import SwiftUI
import SwiftData

enum QuantitySheetMode {
    case checkIn
    case checkOut
}

/// Shared by every check-in/out entry point (hub rows, scan, manual pick, item detail).
/// Shows batch chips only when checking out an item with 2+ lots, per FR-2.2.
struct QuantitySheetView: View {
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss

    let item: Item
    let mode: QuantitySheetMode

    @State private var quantity: Double
    @State private var expDate: Date
    @State private var selectedLot: Lot?
    @State private var errorMessage: String?

    init(item: Item, mode: QuantitySheetMode, preselectedLot: Lot? = nil) {
        self.item = item
        self.mode = mode
        _quantity = State(initialValue: 1)
        _expDate = State(initialValue: Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now)
        _selectedLot = State(initialValue: preselectedLot ?? item.sortedLots.first)
    }

    private var stepSize: Double { item.kind == .unit ? 1 : (item.unit == "ml" || item.unit == "g" ? 50 : 1) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .checkIn ? "Check In" : "Check Out")
                    .trackedUppercase()
                    .font(LarderFont.eyebrow())
                    .foregroundStyle(Color.larderSecondaryText)
                Text(item.name)
                    .font(LarderFont.screenTitle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider().overlay(Color.larderDivider)

            VStack(alignment: .leading, spacing: 24) {
                if mode == .checkOut, item.sortedLots.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Batch")
                            .trackedUppercase()
                            .font(LarderFont.eyebrow())
                            .foregroundStyle(Color.larderSecondaryText)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(item.sortedLots) { lot in
                                    BatchChip(
                                        label: "\(item.formattedQuantity(lot.qty)) · \(lot.exp.formatted(.iso8601.year().month().day()))",
                                        isSelected: selectedLot?.id == lot.id
                                    ) {
                                        selectedLot = lot
                                    }
                                }
                            }
                        }
                    }
                }

                if mode == .checkIn {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Best Before")
                            .trackedUppercase()
                            .font(LarderFont.eyebrow())
                            .foregroundStyle(Color.larderSecondaryText)
                        DatePicker("", selection: $expDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Quantity")
                        .trackedUppercase()
                        .font(LarderFont.eyebrow())
                        .foregroundStyle(Color.larderSecondaryText)
                    HStack {
                        Button {
                            quantity = max(stepSize, quantity - stepSize)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 44, height: 44)
                                .overlay(Rectangle().strokeBorder(Color.larderInk, lineWidth: 1))
                        }
                        Text(item.formattedQuantity(quantity))
                            .font(LarderFont.quantityValue())
                            .frame(maxWidth: .infinity)
                        Button {
                            quantity += stepSize
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 44, height: 44)
                                .overlay(Rectangle().strokeBorder(Color.larderInk, lineWidth: 1))
                        }
                    }
                    .foregroundStyle(Color.larderInk)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.larderAccent)
                }
            }
            .padding(20)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                PrimaryButton(title: mode == .checkIn ? "Confirm Check In" : "Confirm Check Out") {
                    confirm()
                }
                SecondaryButton(title: "Cancel") {
                    dismiss()
                }
            }
            .padding(20)
        }
        .background(Color.larderBackground.ignoresSafeArea())
    }

    private func confirm() {
        switch mode {
        case .checkIn:
            StockService.checkIn(item: item, qty: quantity, exp: expDate, context: context)
            toastCenter.show("Checked in \(item.formattedQuantity(quantity))")
            dismiss()
        case .checkOut:
            do {
                try StockService.checkOut(item: item, qty: quantity, preferredLot: selectedLot, context: context)
                toastCenter.show("Checked out \(item.formattedQuantity(quantity))")
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
