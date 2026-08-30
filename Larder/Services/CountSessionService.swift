import Foundation

enum CountSessionServiceError: LocalizedError {
    case insufficientStock(itemName: String)

    var errorDescription: String? {
        switch self {
        case .insufficientStock(let itemName):
            return "Not enough \"\(itemName)\" on hand to apply this count — it may have changed since the count started."
        }
    }
}

/// Owns stock-take session lifecycle: starting a session against the current catalog,
/// applying the diff as adjustment transactions, or discarding it untouched (FR-7.1/FR-7.3).
enum CountSessionService {

    private static let nextSessionNumberKey = "larder.nextCountSessionNumber"

    /// Creates one `CountLine` per catalog item, yielding periodically so this doesn't block the
    /// main thread for one long, unresponsive stretch at catalog scale — each `addCountLine` call
    /// is a Firestore write applied to the local cache synchronously, so a 5,000-item catalog is
    /// still 5,000 synchronous calls; yielding lets SwiftUI keep processing input/rendering (e.g.
    /// the caller's `ProgressView`) between chunks instead of freezing until the whole loop finishes.
    @MainActor
    static func startSession(mode: CountMode, blindCount: Bool, items: [Item], store: CatalogWriting) async -> CountSession {
        let defaults = UserDefaults.standard
        let number = defaults.integer(forKey: nextSessionNumberKey)
        let sessionNumber = number == 0 ? 501 : number
        defaults.set(sessionNumber + 1, forKey: nextSessionNumberKey)

        let session = CountSession(sessionNumber: sessionNumber, mode: mode, blindCount: blindCount)
        try? store.addCountSession(session)

        for (index, item) in items.enumerated() {
            let bookQty = CatalogDerivation.onHandTotal(itemId: item.id, transactions: store.transactions)
            let line = CountLine(itemId: item.id, bookQtyAtStart: bookQty)
            try? store.addCountLine(line, sessionId: session.id)

            if index % 200 == 199 {
                await Task.yield()
            }
        }

        return session
    }

    /// Writes one signed adjustment per differing line and closes the session (FR-7.3).
    ///
    /// Two-pass validate-then-apply: a mid-loop `insufficientStock` throw would otherwise leave
    /// earlier lines already written with no rollback, and the session never advanced to
    /// `.applied` — stuck neither applied nor discarded. Pass 1 is a pure feasibility check (no
    /// write at all) across every differing line; only once all of them are known-good does pass 2
    /// write anything.
    @MainActor
    static func apply(_ session: CountSession, lines: [CountLine], items: [Item], store: CatalogWriting) throws {
        let differingLines = lines.filter { $0.countedQty != nil && $0.countedQty != $0.bookQtyAtStart }
        let itemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        for line in differingLines {
            guard StockService.canApplyAdjustment(itemId: line.itemId, delta: line.delta, transactions: store.transactions) else {
                throw CountSessionServiceError.insufficientStock(itemName: itemsById[line.itemId]?.name ?? "item")
            }
        }

        for line in differingLines {
            let reason = AdjustReason(rawValue: line.reasonTag ?? AdjustReason.miscount.rawValue) ?? .miscount
            try StockService.applyAdjustment(itemId: line.itemId, delta: line.delta, reason: reason, store: store)
        }

        var updated = session
        updated.status = .applied
        try store.updateCountSession(updated)
    }

    @MainActor
    static func discard(_ session: CountSession, store: CatalogWriting) throws {
        var updated = session
        updated.status = .discarded
        try store.updateCountSession(updated)
    }
}
