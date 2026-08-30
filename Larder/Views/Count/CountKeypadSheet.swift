import SwiftUI

/// FR-7.1/FR-7.2: numeric entry for one count line, defaulting to blank rather than the book
/// value, and hiding the book quantity entirely when blind-count mode is on.
struct CountKeypadSheet: View {
    @Environment(CatalogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let line: CountLine
    let sessionId: String
    let blindCount: Bool

    @State private var enteredText: String = ""

    private var item: Item? { store.item(id: line.itemId) }

    private var parsedValue: Double? {
        Double(enteredText)
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(item?.name ?? "Deleted item")
                    .font(LarderFont.screenTitle())
                if blindCount {
                    Text("expected hidden until review")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.larderSecondaryText)
                } else if let item {
                    Text("book \(item.formattedQuantity(line.bookQtyAtStart))")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.larderSecondaryText)
                }
            }
            .padding(.top, 24)

            TextField("Actual count", text: $enteredText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 40, weight: .bold))
                .padding()
                .overlay(Rectangle().strokeBorder(Color.larderDivider, lineWidth: 1))
                .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 10) {
                PrimaryButton(title: "Save", isEnabled: parsedValue != nil) {
                    var updated = line
                    updated.countedQty = parsedValue
                    try? store.updateCountLine(updated, sessionId: sessionId)
                    dismiss()
                }
                SecondaryButton(title: "Cancel") { dismiss() }
            }
            .padding(20)
        }
        .background(Color.larderBackground.ignoresSafeArea())
    }
}
