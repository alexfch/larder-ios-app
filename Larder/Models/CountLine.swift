import Foundation

/// Firestore document shape for `/households/{householdId}/countSessions/{sessionId}/lines/{lineId}`
/// (ADR-0003) — a subcollection rather than an array field on the session document, so a
/// 5,000-item stock-take doesn't risk the 1 MiB document cap or rewrite the whole array on every
/// single line update.
struct CountLine: Identifiable, Codable, Hashable {
    var id: String
    var itemId: String
    var bookQtyAtStart: Double
    var countedQty: Double?
    var reasonTag: String?

    init(
        id: String = UUID().uuidString,
        itemId: String,
        bookQtyAtStart: Double,
        countedQty: Double? = nil,
        reasonTag: String? = AdjustReason.miscount.rawValue
    ) {
        self.id = id
        self.itemId = itemId
        self.bookQtyAtStart = bookQtyAtStart
        self.countedQty = countedQty
        self.reasonTag = reasonTag
    }

    var delta: Double {
        (countedQty ?? bookQtyAtStart) - bookQtyAtStart
    }
}
