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
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: exp)).day ?? 0
    }

    var isExpiringSoon: Bool {
        daysUntilExpiry <= 14
    }
}
