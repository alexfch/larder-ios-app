import SwiftUI

/// F8/FR-7.1/FR-7.2: starts (or resumes) a stock-take session with Checklist or Scan sweep
/// entry, a numeric keypad per line, and an optional blind-count mode.
struct CountSessionView: View {
    /// Single source of truth for "what's on screen right now," replacing three independent
    /// `@State` optionals/booleans each backing its own `.sheet()` modifier — the structural
    /// pattern the architecture review flagged as repeated across 5 screens. `handleScan` used to
    /// dismiss the scanner and open the keypad sheet as two separate state mutations in the same
    /// closure; that's now one reassignment of `activeSheet`.
    private enum ActiveSheet: Identifiable {
        case keypad(CountLine)
        case scanner
        case review

        var id: String {
            switch self {
            case .keypad(let line): return "keypad-\(line.id)"
            case .scanner: return "scanner"
            case .review: return "review"
            }
        }
    }

    @Environment(CatalogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var inProgressSessions: [CountSession] {
        store.countSessions.filter { $0.status == .inProgress }
    }

    @State private var session: CountSession?
    @State private var activeSheet: ActiveSheet?

    private var lines: [CountLine] {
        guard let session else { return [] }
        return store.lines(for: session.id)
    }

    private var sortedLines: [CountLine] {
        lines.sorted { (store.item(id: $0.itemId)?.name ?? "") < (store.item(id: $1.itemId)?.name ?? "") }
    }

    private var countedLines: [CountLine] {
        lines.filter { $0.countedQty != nil }
    }

    private var differingLines: [CountLine] {
        lines.filter { $0.countedQty != nil && $0.countedQty != $0.bookQtyAtStart }
    }

    var body: some View {
        NavigationStack {
            content
        }
        .task {
            await ensureSession()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let session {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session \(session.displayNumber)")
                            .trackedUppercase()
                            .font(LarderFont.eyebrow())
                            .foregroundStyle(Color.larderSecondaryText)
                        Text("Count")
                            .font(LarderFont.screenTitle())
                    }
                    Spacer()
                    Text("\(countedLines.count)/\(lines.count)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.larderAccent)
                }
                .padding(20)

                ProgressView(value: Double(countedLines.count), total: Double(max(lines.count, 1)))
                    .tint(Color.larderAccent)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                Picker("Mode", selection: Binding(
                    get: { session.mode },
                    set: { setMode($0) }
                )) {
                    Text("Checklist").tag(CountMode.checklist)
                    Text("Scan sweep").tag(CountMode.scanSweep)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                Toggle("Blind count (hide book quantity)", isOn: Binding(
                    get: { session.blindCount },
                    set: { newValue in setBlindCount(newValue) }
                ))
                .font(.system(size: 13))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                Text(session.mode == .checklist
                     ? "Tap a line to key in what is actually on the shelf. Untouched lines are left alone."
                     : "Scan a barcode to tick that line at book quantity. Scan again to correct it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.larderSecondaryText)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                Divider().overlay(Color.larderDivider)

                List {
                    ForEach(sortedLines) { line in
                        Button {
                            if session.mode == .checklist {
                                activeSheet = .keypad(line)
                            }
                        } label: {
                            CountLineRow(
                                line: line,
                                item: store.item(id: line.itemId),
                                earliestBestBefore: CatalogDerivation.earliestBestBefore(itemId: line.itemId, transactions: store.transactions),
                                blindCount: session.blindCount
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        if session.mode == .scanSweep {
                            PrimaryButton(title: "Scan") { activeSheet = .scanner }
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }

                        HStack {
                            Text("\(countedLines.count) counted · \(differingLines.count) differing")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.larderSecondaryText)
                            Spacer()
                            SecondaryButton(title: "Review", isEnabled: !countedLines.isEmpty) {
                                activeSheet = .review
                            }
                            .frame(width: 120)
                        }
                        .padding(20)
                    }
                    .background(Color.larderBackground)
                }
            }
            .background(Color.larderBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .keypad(let line):
                    CountKeypadSheet(line: line, sessionId: session.id, blindCount: session.blindCount)
                case .scanner:
                    BarcodeScannerView { code in
                        handleScan(code: code, session: session)
                    }
                case .review:
                    CountReviewView(session: session, onFinish: { dismiss() })
                }
            }
        } else {
            ProgressView()
        }
    }

    private func ensureSession() async {
        if let existing = inProgressSessions.first {
            session = existing
            store.observeLines(for: existing.id)
        } else {
            let newSession = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: store.items, store: store)
            store.observeLines(for: newSession.id)
            session = newSession
        }
    }

    private func setMode(_ newMode: CountMode) {
        guard var session else { return }
        session.mode = newMode
        self.session = session
        try? store.updateCountSession(session)
    }

    private func setBlindCount(_ newValue: Bool) {
        guard var session else { return }
        session.blindCount = newValue
        self.session = session
        try? store.updateCountSession(session)
    }

    private func handleScan(code: String, session: CountSession) {
        // Resolve the barcode against the catalog first, via the shared, indexed lookup — not a
        // scan through every line's item barcode, which was the same reimplemented-linear-scan
        // pattern the architecture review flagged at every other scan site.
        guard let item = store.item(matchingBarcode: code),
              let line = lines.first(where: { $0.itemId == item.id }) else {
            activeSheet = nil
            return
        }
        if line.countedQty == nil {
            var updated = line
            updated.countedQty = line.bookQtyAtStart
            try? store.updateCountLine(updated, sessionId: session.id)
            activeSheet = nil
        } else {
            activeSheet = .keypad(line)
        }
    }
}

struct CountLineRow: View {
    let line: CountLine
    let item: Item?
    let earliestBestBefore: Date?
    let blindCount: Bool

    private var formattedBestBefore: String {
        earliestBestBefore?.formatted(.iso8601.year().month().day()) ?? "—"
    }

    var body: some View {
        HStack {
            Image(systemName: line.countedQty != nil ? "checkmark.square.fill" : "square")
                .foregroundStyle(line.countedQty != nil ? Color.larderAccent : Color.larderSecondaryText)

            VStack(alignment: .leading, spacing: 2) {
                Text(item?.name ?? "Deleted item")
                    .font(LarderFont.rowTitle())
                if blindCount && line.countedQty == nil {
                    Text("best before \(formattedBestBefore)")
                        .font(LarderFont.rowSubtitle())
                        .foregroundStyle(Color.larderSecondaryText)
                } else if let item {
                    Text("book \(item.formattedQuantity(line.bookQtyAtStart)) · bb \(formattedBestBefore)")
                        .font(LarderFont.rowSubtitle())
                        .foregroundStyle(Color.larderSecondaryText)
                }
            }
            Spacer()
            if let counted = line.countedQty, let item {
                Text(item.formattedQuantity(counted))
                    .font(.system(size: 15, weight: .bold))
            } else {
                Text("—")
                    .foregroundStyle(Color.larderSecondaryText)
            }
        }
        .padding(.vertical, 6)
    }
}
