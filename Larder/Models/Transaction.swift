import Foundation
import SwiftData

@Model
final class Transaction {
    var id: UUID
    var item: Item?
    var action: TransactionAction
    var qty: Double
    /// The date of the lot this transaction affected.
    var exp: Date
    var occurredAt: Date
    /// Set only on `.adjust` transactions produced by a count session.
    var reasonTag: String?

    init(
        id: UUID = UUID(),
        item: Item? = nil,
        action: TransactionAction,
        qty: Double,
        exp: Date,
        occurredAt: Date = .now,
        reasonTag: String? = nil
    ) {
        self.id = id
        self.item = item
        self.action = action
        self.qty = qty
        self.exp = exp
        self.occurredAt = occurredAt
        self.reasonTag = reasonTag
    }
}
