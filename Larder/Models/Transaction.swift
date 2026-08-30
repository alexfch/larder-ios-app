import Foundation

/// Firestore document shape for the flat, household-level `/households/{householdId}/transactions/{transactionId}`
/// collection (ADR-0003). This is the only thing ordinary stock movements ever write — check-in,
/// check-out, and count adjustments are each a new document, never a mutated shared field — which
/// is what lets them apply safely offline with no risk of conflicting with another device's
/// concurrent write. `CatalogDerivation` groups these by `(itemId, exp)` to derive each item's
/// batches ("lots"), on-hand total, and earliest best-before.
struct Transaction: Identifiable, Codable, Hashable {
    var id: String
    var itemId: String
    var action: TransactionAction
    var qty: Double
    /// The date of the lot this transaction affects.
    var exp: Date
    var occurredAt: Date
    /// Set only on `.adjust` transactions produced by a count session.
    var reasonTag: String?

    init(
        id: String = UUID().uuidString,
        itemId: String,
        action: TransactionAction,
        qty: Double,
        exp: Date,
        occurredAt: Date = .now,
        reasonTag: String? = nil
    ) {
        self.id = id
        self.itemId = itemId
        self.action = action
        self.qty = qty
        self.exp = exp
        self.occurredAt = occurredAt
        self.reasonTag = reasonTag
    }
}
