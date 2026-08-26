import Foundation
import SwiftData

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
/// edit/remove logic required by FR-6.1. Every mutation is applied directly to SwiftData
/// model objects already tracked by the caller's `ModelContext`.
enum StockService {

    // MARK: Check-in (FR-2.1)

    @discardableResult
    static func checkIn(item: Item, qty: Double, exp: Date, context: ModelContext) -> Transaction {
        let normalizedExp = Calendar.current.startOfDay(for: exp)
        addToLot(item: item, exp: normalizedExp, qty: qty, context: context)

        let transaction = Transaction(item: item, action: .checkIn, qty: qty, exp: normalizedExp)
        context.insert(transaction)
        item.transactions.append(transaction)
        return transaction
    }

    // MARK: Check-out (FR-2.2)

    /// Draws from `preferredLot` first (or the earliest lot if nil), cascading to the next
    /// earliest lot(s) if the request exceeds what one lot holds. Writes one transaction per
    /// lot drawn from, so each stays individually reversible and tied to one batch date.
    @discardableResult
    static func checkOut(item: Item, qty: Double, preferredLot: Lot? = nil, context: ModelContext) throws -> [Transaction] {
        var remaining = qty
        var order = item.sortedLots
        if let preferredLot, let index = order.firstIndex(where: { $0.id == preferredLot.id }) {
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
            lot.qty -= draw
            remaining -= draw

            let transaction = Transaction(item: item, action: .checkOut, qty: draw, exp: lot.exp)
            context.insert(transaction)
            item.transactions.append(transaction)
            createdTransactions.append(transaction)

            if lot.qty <= 0 {
                removeLot(lot, from: item, context: context)
            }
        }

        return createdTransactions
    }

    // MARK: Correctable history (FR-6.1)

    static func edit(_ transaction: Transaction, newQty: Double, newExp: Date, context: ModelContext) throws {
        guard let item = transaction.item else { return }
        let normalizedNewExp = Calendar.current.startOfDay(for: newExp)
        let originalAction = transaction.action
        let originalQty = transaction.qty
        let originalExp = transaction.exp

        reverseEffect(of: transaction, context: context)
        do {
            try applyEffect(item: item, action: originalAction, qty: newQty, exp: normalizedNewExp, context: context)
        } catch {
            // Restore the original effect so a failed edit never leaves stock half-reversed.
            try? applyEffect(item: item, action: originalAction, qty: originalQty, exp: originalExp, context: context)
            throw error
        }

        transaction.qty = newQty
        transaction.exp = normalizedNewExp
    }

    static func remove(_ transaction: Transaction, context: ModelContext) {
        reverseEffect(of: transaction, context: context)
        transaction.item?.transactions.removeAll { $0.id == transaction.id }
        context.delete(transaction)
    }

    // MARK: Stock-take adjustments (FR-7.3)

    /// Writes one signed adjustment transaction against the item's earliest lot. A positive
    /// delta means the count found more than the book (IN-like); negative means less (OUT-like).
    @discardableResult
    static func applyAdjustment(item: Item, delta: Double, reason: AdjustReason, context: ModelContext) throws -> Transaction {
        let exp = item.sortedLots.first?.exp ?? Calendar.current.startOfDay(for: .now)
        if delta >= 0 {
            addToLot(item: item, exp: exp, qty: delta, context: context)
        } else {
            try removeFromLots(item: item, exp: exp, qty: -delta, context: context)
        }

        let transaction = Transaction(item: item, action: .adjust, qty: delta, exp: exp, reasonTag: reason.rawValue)
        context.insert(transaction)
        item.transactions.append(transaction)
        return transaction
    }

    // MARK: Private helpers

    private static func reverseEffect(of transaction: Transaction, context: ModelContext) {
        guard let item = transaction.item else { return }
        switch transaction.action {
        case .checkIn:
            try? removeFromLots(item: item, exp: transaction.exp, qty: transaction.qty, context: context)
        case .checkOut:
            addToLot(item: item, exp: transaction.exp, qty: transaction.qty, context: context)
        case .adjust:
            if transaction.qty >= 0 {
                try? removeFromLots(item: item, exp: transaction.exp, qty: transaction.qty, context: context)
            } else {
                addToLot(item: item, exp: transaction.exp, qty: -transaction.qty, context: context)
            }
        }
    }

    private static func applyEffect(item: Item, action: TransactionAction, qty: Double, exp: Date, context: ModelContext) throws {
        switch action {
        case .checkIn:
            addToLot(item: item, exp: exp, qty: qty, context: context)
        case .checkOut:
            try removeFromLots(item: item, exp: exp, qty: qty, context: context)
        case .adjust:
            if qty >= 0 {
                addToLot(item: item, exp: exp, qty: qty, context: context)
            } else {
                try removeFromLots(item: item, exp: exp, qty: -qty, context: context)
            }
        }
    }

    private static func addToLot(item: Item, exp: Date, qty: Double, context: ModelContext) {
        if let existing = item.lots.first(where: { Calendar.current.isDate($0.exp, inSameDayAs: exp) }) {
            existing.qty += qty
        } else {
            let lot = Lot(item: item, qty: qty, exp: exp)
            context.insert(lot)
            item.lots.append(lot)
        }
    }

    /// Removes `qty` starting from the lot dated `exp` (recreating it if it no longer exists,
    /// which happens when reversing a check-out that emptied the lot), cascading to the next
    /// earliest lot(s) if that single lot doesn't hold enough.
    private static func removeFromLots(item: Item, exp: Date, qty: Double, context: ModelContext) throws {
        var remaining = qty
        if let primary = item.lots.first(where: { Calendar.current.isDate($0.exp, inSameDayAs: exp) }) {
            let draw = min(primary.qty, remaining)
            primary.qty -= draw
            remaining -= draw
            if primary.qty <= 0 {
                removeLot(primary, from: item, context: context)
            }
        }

        guard remaining > 0 else { return }

        let cascade = item.sortedLots
        guard cascade.reduce(0, { $0 + $1.qty }) >= remaining else {
            throw StockServiceError.insufficientStock
        }
        for lot in cascade where remaining > 0 {
            let draw = min(lot.qty, remaining)
            guard draw > 0 else { continue }
            lot.qty -= draw
            remaining -= draw
            if lot.qty <= 0 {
                removeLot(lot, from: item, context: context)
            }
        }
    }

    private static func removeLot(_ lot: Lot, from item: Item, context: ModelContext) {
        item.lots.removeAll { $0.id == lot.id }
        context.delete(lot)
    }
}
