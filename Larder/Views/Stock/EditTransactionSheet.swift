import SwiftUI
import SwiftData

/// FR-6.1: reopens pre-filled with the movement's current quantity/date; saving reverses the
/// old effect and applies the new values as a single atomic update via `StockService.edit`.
struct EditTransactionSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss

    let item: Item
    let transaction: Transaction

    @State private var quantity: Double
    @State private var expDate: Date
    @State private var errorMessage: String?

    init(item: Item, transaction: Transaction) {
        self.item = item
        self.transaction = transaction
        _quantity = State(initialValue: abs(transaction.qty))
        _expDate = State(initialValue: transaction.exp)
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
                Section("Batch Date") {
                    DatePicker("Date", selection: $expDate, displayedComponents: .date)
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
            try StockService.edit(transaction, newQty: signedQty, newExp: expDate, context: context)
            toastCenter.show("Movement updated")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
