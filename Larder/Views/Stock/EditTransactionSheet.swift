import SwiftUI

/// FR-6.1: reopens pre-filled with the movement's current quantity/date; saving updates the
/// transaction document directly via `StockService.edit` (see that method's doc comment for why
/// this no longer needs a separate "reverse, then reapply" step now that lots are derived).
struct EditTransactionSheet: View {
    @Environment(CatalogStore.self) private var store
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss

    let item: Item
    let transaction: Transaction

    @State private var quantity: Double
    /// Always a concrete date, even when `transaction.exp` was nil -- only read when
    /// `item.noExpirationDate` is false, matching `QuantitySheetView`'s own Best Before section.
    /// Falls back to 30 days out for the rare case of a dated item whose existing transaction
    /// somehow has no date (e.g. `noExpirationDate` was toggled off after this batch was checked
    /// in), same fallback `QuantitySheetView` uses for a fresh check-in.
    @State private var expDate: Date
    @State private var errorMessage: String?

    init(item: Item, transaction: Transaction) {
        self.item = item
        self.transaction = transaction
        _quantity = State(initialValue: abs(transaction.qty))
        _expDate = State(initialValue: transaction.exp ?? Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quantity") {
                    HStack {
                        Text(transaction.action.rawValue)
                            .foregroundStyle(Color.larderSecondaryText)
                        Spacer()
                        TextField("Quantity", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if !item.noExpirationDate {
                    Section("Batch Date") {
                        DatePicker("Date", selection: $expDate, displayedComponents: .date)
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Color.larderAccent)
                }
            }
            .navigationTitle("Edit Movement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        do {
            let signedQty = transaction.action == .adjust ? (transaction.qty < 0 ? -quantity : quantity) : quantity
            let newExp: Date? = item.noExpirationDate ? nil : expDate
            try StockService.edit(transaction, newQty: signedQty, newExp: newExp, store: store)
            toastCenter.show("Movement updated")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
