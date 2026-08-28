import SwiftUI
import SwiftData

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

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Item.name) private var allItems: [Item]
    @Query private var allSessions: [CountSession]

    private var inProgressSessions: [CountSession] {
        allSessions.filter { $0.status == .inProgress }
    }

    @State private var session: CountSession?
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        NavigationStack {
            content
        }
        .onAppear(perform: ensureSession)
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
                    Text("\(session.countedLines.count)/\(session.lines.count)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.larderAccent)
                }
                .padding(20)

                ProgressView(value: Double(session.countedLines.count), total: Double(max(session.lines.count, 1)))
                    .tint(Color.larderAccent)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                Picker("Mode", selection: Binding(
                    get: { session.mode },
                    set: { session.mode = $0 }
                )) {
                    Text("Checklist").tag(CountMode.checklist)
                    Text("Scan sweep").tag(CountMode.scanSweep)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                Toggle("Blind count (hide book quantity)", isOn: Binding(
                    get: { session.blindCount },
                    set: { session.blindCount = $0 }
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
                    ForEach(session.lines.sorted(by: { ($0.item?.name ?? "") < ($1.item?.name ?? "") })) { line in
                        Button {
                            if session.mode == .checklist {
                                activeSheet = .keypad(line)
                            }
                        } label: {
                            CountLineRow(line: line, blindCount: session.blindCount)
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
                            Text("\(session.countedLines.count) counted · \(session.differingLines.count) differing")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.larderSecondaryText)
                            Spacer()
                            SecondaryButton(title: "Review", isEnabled: !session.countedLines.isEmpty) {
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
                    CountKeypadSheet(line: line, blindCount: session.blindCount)
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

    private func ensureSession() {
        if let existing = inProgressSessions.first {
            session = existing
        } else {
            session = CountSessionService.startSession(mode: .checklist, blindCount: false, items: allItems, context: context)
        }
    }

    private func handleScan(code: String, session: CountSession) {
        guard let line = session.lines.first(where: { $0.item?.barcode == code }) else {
            activeSheet = nil
            return
        }
        if line.countedQty == nil {
            line.countedQty = line.bookQtyAtStart
            activeSheet = nil
        } else {
            activeSheet = .keypad(line)
        }
    }
}

struct CountLineRow: View {
    let line: CountLine
    let blindCount: Bool

    var body: some View {
        HStack {
            Image(systemName: line.countedQty != nil ? "checkmark.square.fill" : "square")
                .foregroundStyle(line.countedQty != nil ? Color.larderAccent : Color.larderSecondaryText)

            VStack(alignment: .leading, spacing: 2) {
                Text(line.item?.name ?? "Deleted item")
                    .font(LarderFont.rowTitle())
                if blindCount && line.countedQty == nil {
                    Text("best before \(line.item?.earliestBestBefore?.formatted(.iso8601.year().month().day()) ?? "—")")
                        .font(LarderFont.rowSubtitle())
                        .foregroundStyle(Color.larderSecondaryText)
                } else if let item = line.item {
                    Text("book \(item.formattedQuantity(line.bookQtyAtStart)) · bb \(item.earliestBestBefore?.formatted(.iso8601.year().month().day()) ?? "—")")
                        .font(LarderFont.rowSubtitle())
                        .foregroundStyle(Color.larderSecondaryText)
                }
            }
            Spacer()
            if let counted = line.countedQty, let item = line.item {
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
