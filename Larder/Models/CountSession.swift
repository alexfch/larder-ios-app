import Foundation
import SwiftData

@Model
final class CountSession {
    var id: UUID
    var sessionNumber: Int
    var mode: CountMode
    var blindCount: Bool
    var status: CountStatus
    var startedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CountLine.session)
    var lines: [CountLine] = []

    init(
        id: UUID = UUID(),
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

    var countedLines: [CountLine] {
        lines.filter { $0.countedQty != nil }
    }

    var differingLines: [CountLine] {
        lines.filter { $0.countedQty != nil && $0.countedQty != $0.bookQtyAtStart }
    }
}
