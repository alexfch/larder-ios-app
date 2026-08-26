import Foundation
import SwiftData

@Model
final class CountLine {
    var id: UUID
    var session: CountSession?
    var item: Item?
    var bookQtyAtStart: Double
    var countedQty: Double?
    var reasonTag: String?

    init(
        id: UUID = UUID(),
        session: CountSession? = nil,
        item: Item? = nil,
        bookQtyAtStart: Double,
        countedQty: Double? = nil,
        reasonTag: String? = AdjustReason.miscount.rawValue
    ) {
        self.id = id
        self.session = session
        self.item = item
        self.bookQtyAtStart = bookQtyAtStart
        self.countedQty = countedQty
        self.reasonTag = reasonTag
    }

    var delta: Double {
        (countedQty ?? bookQtyAtStart) - bookQtyAtStart
    }
}
