import Foundation
import SwiftData

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
    /// main thread for one long, unresponsive stretch at catalog scale. `ModelContext` isn't
    /// `Sendable` and is bound to whichever actor created it — here, the view hierarchy's
    /// main-actor context — so this can't move to a `@ModelActor` background actor the way other
    /// SwiftData background work normally would; the writes have to stay on the main actor
    /// either way. Making the loop cooperative (instead of one uninterrupted synchronous pass)
    /// is what's actually achievable here: SwiftUI can still process input and render — e.g. the
    /// caller's `ProgressView` — between chunks instead of freezing until the whole loop finishes.
    ///
    /// Note this does NOT append each line to `session.lines` manually: `CountLine.init(session:)`
    /// already sets that side of the relationship, and `CountSession.lines`'s declared
    /// `inverse: \CountLine.session` means SwiftData mirrors it automatically. The redundant
    /// manual append that used to be here was the dominant cost at catalog scale — repeatedly
    /// appending to a large SwiftData-managed to-many relationship array turned out to be far
    /// more expensive than the equivalent work already happening implicitly via the inverse.
    @MainActor
    static func startSession(mode: CountMode, blindCount: Bool, items: [Item], context: ModelContext) async -> CountSession {
        let defaults = UserDefaults.standard
        let number = defaults.integer(forKey: nextSessionNumberKey)
        let sessionNumber = number == 0 ? 501 : number
        defaults.set(sessionNumber + 1, forKey: nextSessionNumberKey)

        let session = CountSession(sessionNumber: sessionNumber, mode: mode, blindCount: blindCount)
        context.insert(session)

        for (index, item) in items.enumerated() {
            let line = CountLine(session: session, item: item, bookQtyAtStart: item.onHandTotal)
            context.insert(line)

            if index % 200 == 199 {
                await Task.yield()
            }
        }

        return session
    }

    /// Writes one signed adjustment per differing line and closes the session (FR-7.3).
    ///
    /// Two-pass validate-then-apply: a mid-loop `insufficientStock` throw used to leave earlier
    /// lines already mutated with no rollback, and `session.status` never advanced — a session
    /// stuck neither applied nor discarded. Pass 1 is a pure feasibility check (no `ModelContext`
    /// touched at all) across every differing line; only once all of them are known-good does
    /// pass 2 mutate anything, wrapped in `context.transaction` as a defensive atomicity boundary
    /// in case something still throws unexpectedly once mutation starts.
    static func apply(_ session: CountSession, context: ModelContext) throws {
        for line in session.differingLines {
            guard let item = line.item else { continue }
            guard StockService.canApplyAdjustment(item: item, delta: line.delta) else {
                throw CountSessionServiceError.insufficientStock(itemName: item.name)
            }
        }

        try context.transaction {
            for line in session.differingLines {
                guard let item = line.item else { continue }
                let reason = AdjustReason(rawValue: line.reasonTag ?? AdjustReason.miscount.rawValue) ?? .miscount
                try StockService.applyAdjustment(item: item, delta: line.delta, reason: reason, context: context)
            }
            session.status = .applied
        }
    }

    static func discard(_ session: CountSession) {
        session.status = .discarded
    }
}
