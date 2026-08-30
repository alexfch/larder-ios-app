import Foundation

enum StockServiceError: LocalizedError {
    case insufficientStock

    var errorDescription: String? {
        switch self {
        case .insufficientStock:
            return "Not enough stock on hand to complete this action."
        }
    }
}

/// Owns all batch/lot math: check-in, FIFO/selected-batch check-out, and the reversible
/// edit/remove logic required by FR-6.1.
///
/// Per ADR-0003, this is substantially simpler than its SwiftData predecessor: since a "lot" is
/// now a derived grouping of `Transaction` documents (`CatalogDerivation`) rather than a stored,
/// mutated-in-place entity, there's no lot object to find-and-adjust — every mutation here is
/// either creating a new transaction document (check-in, check-out, adjust) or editing/deleting
/// exactly one existing one (correctable history). Feasibility ("would this ever ask for more
/// than is on hand?") is checked by re-deriving lot totals against a hypothetical transaction
/// list that includes the pending change, rather than the old step-wise "reverse, then reapply"
/// dance SwiftData's in-place `Lot.qty` mutation required.
enum StockService {

    // MARK: Check-in (FR-2.1)

    @MainActor
    @discardableResult
    static func checkIn(itemId: String, qty: Double, exp: Date, store: CatalogWriting) throws -> Transaction {
        let normalizedExp = Calendar.current.startOfDay(for: exp)
        let transaction = Transaction(itemId: itemId, action: .checkIn, qty: qty, exp: normalizedExp)
        try store.addTransaction(transaction)
        return transaction
    }

    // MARK: Check-out (FR-2.2)

    /// Draws from `preferredLot` first (or the earliest lot if nil), cascading to the next
    /// earliest lot(s) if the request exceeds what one lot holds. Writes one transaction per
    /// lot drawn from, so each stays individually reversible and tied to one batch date.
    @MainActor
    @discardableResult
    static func checkOut(itemId: String, qty: Double, preferredLot: Lot? = nil, store: CatalogWriting) throws -> [Transaction] {
        var remaining = qty
        var order = CatalogDerivation.sortedLots(itemId: itemId, transactions: store.transactions)
        if let preferredLot, let index = order.firstIndex(where: { $0.exp == preferredLot.exp }) {
            order.remove(at: index)
            order.insert(preferredLot, at: 0)
        }

        guard order.reduce(0, { $0 + $1.qty }) >= qty else {
            throw StockServiceError.insufficientStock
        }

        var createdTransactions: [Transaction] = []
        for lot in order where remaining > 0 {
            let draw = min(lot.qty, remaining)
            guard draw > 0 else { continue }
            remaining -= draw

            let transaction = Transaction(itemId: itemId, action: .checkOut, qty: draw, exp: lot.exp)
            try store.addTransaction(transaction)
            createdTransactions.append(transaction)
        }

        return createdTransactions
    }

    // MARK: Correctable history (FR-6.1)

    /// Reversing-then-reapplying used to matter because SwiftData's `Lot.qty` was a stored,
    /// mutated-in-place total shared across transactions on the same batch. Now it's just: build
    /// the transaction list as it would look *after* the edit, and check that no lot in that
    /// hypothetical world ever goes negative — one arithmetic pass, no intermediate lot state to
    /// protect.
    @MainActor
    static func edit(_ transaction: Transaction, newQty: Double, newExp: Date, store: CatalogWriting) throws {
        let normalizedNewExp = Calendar.current.startOfDay(for: newExp)
        var updated = transaction
        updated.qty = newQty
        updated.exp = normalizedNewExp

        var hypothetical = store.transactions
        if let index = hypothetical.firstIndex(where: { $0.id == transaction.id }) {
            hypothetical[index] = updated
        }
        try assertNoNegativeLots(itemId: transaction.itemId, transactions: hypothetical)

        try store.updateTransaction(updated)
    }

    @MainActor
    static func remove(_ transaction: Transaction, store: CatalogWriting) throws {
        let hypothetical = store.transactions.filter { $0.id != transaction.id }
        try assertNoNegativeLots(itemId: transaction.itemId, transactions: hypothetical)

        store.deleteTransaction(id: transaction.id)
    }

    // MARK: Stock-take adjustments (FR-7.3)

    /// Pure feasibility check for `applyAdjustment` — no write, so callers can validate a whole
    /// batch of adjustments up front before committing to any of them.
    static func canApplyAdjustment(itemId: String, delta: Double, transactions: [Transaction]) -> Bool {
        let exp = CatalogDerivation.sortedLots(itemId: itemId, transactions: transactions).first?.exp
            ?? Calendar.current.startOfDay(for: .now)
        var hypothetical = transactions
        hypothetical.append(Transaction(itemId: itemId, action: .adjust, qty: delta, exp: exp))
        return CatalogDerivation.rawLotTotals(itemId: itemId, transactions: hypothetical).values.allSatisfy { $0 >= -0.0001 }
    }

    /// Writes one signed adjustment transaction against the item's earliest lot. A positive
    /// delta means the count found more than the book (IN-like); negative means less (OUT-like).
    @MainActor
    @discardableResult
    static func applyAdjustment(itemId: String, delta: Double, reason: AdjustReason, store: CatalogWriting) throws -> Transaction {
        let exp = CatalogDerivation.sortedLots(itemId: itemId, transactions: store.transactions).first?.exp
            ?? Calendar.current.startOfDay(for: .now)
        let transaction = Transaction(itemId: itemId, action: .adjust, qty: delta, exp: exp, reasonTag: reason.rawValue)
        try store.addTransaction(transaction)
        return transaction
    }

    // MARK: Private helpers

    private static func assertNoNegativeLots(itemId: String, transactions: [Transaction]) throws {
        let totals = CatalogDerivation.rawLotTotals(itemId: itemId, transactions: transactions)
        guard totals.values.allSatisfy({ $0 >= -0.0001 }) else {
            throw StockServiceError.insufficientStock
        }
    }
}
