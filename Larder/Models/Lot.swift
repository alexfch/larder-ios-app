import Foundation
import SwiftData

@Model
final class Lot {
    var id: UUID
    var item: Item?
    var qty: Double
    var exp: Date

    init(id: UUID = UUID(), item: Item? = nil, qty: Double, exp: Date) {
        self.id = id
        self.item = item
        self.qty = qty
        self.exp = exp
    }

    var daysUntilExpiry: Int {
        exp.daysFromToday
    }

    var isExpiringSoon: Bool {
        daysUntilExpiry <= 14
    }
}
