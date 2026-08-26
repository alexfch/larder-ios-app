import SwiftUI
import SwiftData

/// F9/FR-7.3: shows only the lines that differ from book, each with a reason chip; Apply
/// writes one signed adjustment transaction per line, Discard leaves everything untouched.
struct CountReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss

    let session: CountSession
    /// Invoked after a successful apply/discard so the presenting `CountSessionView` can also
    /// dismiss — the whole count flow closes back to Stock rather than leaving a stale session.
    var onFinish: (() -> Void)? = nil

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if session.differingLines.isEmpty {
                    Spacer()
                    Text("Nothing to adjust — every counted line matched the book.")
                        .foregroundStyle(Color.larderSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(40)
                    Spacer()

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(Color.larderAccent)
                            .padding(.horizontal, 20)
                    }

                    VStack(spacing: 10) {
                        SecondaryButton(title: "Discard") { discard() }
                    }
                    .padding(20)
                } else {
                    List {
                        ForEach(session.differingLines) { line in
                            AdjustLineRow(line: line)
                        }
                    }
                    .listStyle(.plain)
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 10) {
                            if let errorMessage {
                                Text(errorMessage)
                                    .foregroundStyle(Color.larderAccent)
                                    .padding(.horizontal, 20)
                            }
                            PrimaryButton(title: "Apply") { apply() }
                            SecondaryButton(title: "Discard") { discard() }
                        }
                        .padding(20)
                        .background(Color.larderBackground)
                    }
                }
            }
            .background(Color.larderBackground.ignoresSafeArea())
            .navigationTitle("Review \(session.displayNumber)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func apply() {
        do {
            try CountSessionService.apply(session, context: context)
            toastCenter.show("Count applied — balances updated")
            dismiss()
            onFinish?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discard() {
        CountSessionService.discard(session)
        toastCenter.show("Count discarded")
        dismiss()
        onFinish?()
    }
}

struct AdjustLineRow: View {
    let line: CountLine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.item?.name ?? "Deleted item")
                        .font(LarderFont.rowTitle())
                    if let item = line.item {
                        Text("book \(item.formattedQuantity(line.bookQtyAtStart)) → counted \(item.formattedQuantity(line.countedQty ?? line.bookQtyAtStart))")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.larderSecondaryText)
                    }
                }
                Spacer()
                Text(signedDelta)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(line.delta >= 0 ? Color.larderAccent : Color.larderInk)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AdjustReason.allCases) { reason in
                        BatchChip(label: reason.rawValue, isSelected: line.reasonTag == reason.rawValue) {
                            line.reasonTag = reason.rawValue
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var signedDelta: String {
        let magnitude = line.item?.formattedQuantity(abs(line.delta)) ?? "\(abs(line.delta))"
        return (line.delta >= 0 ? "+" : "−") + magnitude
    }
}
