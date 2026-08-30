import Foundation

/// Firestore document shape for `/households/{householdId}/countSessions/{sessionId}` (ADR-0003).
/// Its lines live in a `lines` subcollection rather than an array field here — see `CountLine`.
struct CountSession: Identifiable, Codable, Hashable {
    var id: String
    var sessionNumber: Int
    var mode: CountMode
    var blindCount: Bool
    var status: CountStatus
    var startedAt: Date

    init(
        id: String = UUID().uuidString,
        sessionNumber: Int,
        mode: CountMode,
        blindCount: Bool = false,
        status: CountStatus = .inProgress,
        startedAt: Date = .now
    ) {
        self.id = id
        self.sessionNumber = sessionNumber
        self.mode = mode
        self.blindCount = blindCount
        self.status = status
        self.startedAt = startedAt
    }

    var displayNumber: String {
        "INV-\(sessionNumber)"
    }
}
