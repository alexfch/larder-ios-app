import Foundation

/// A "batch" of one item dated to one best-before date. No longer a stored Firestore document
/// (ADR-0003) — it's a derived grouping of that item's `Transaction` documents sharing an `exp`
/// date, computed by `CatalogDerivation`, exactly mirroring what the old SwiftData `Lot` entity
/// represented but without any field a second device could ever conflict-write.
///
/// `exp` is optional: a product created with `Item.noExpirationDate == true` is always checked
/// in with a nil `exp`, so every one of its lots groups into a single nil-keyed batch rather than
/// being spread across dated ones. See `CatalogDerivation.rawLotTotals` for how that grouping key
/// works.
struct Lot: Identifiable, Hashable {
    var itemId: String
    var qty: Double
    var exp: Date?

    var id: String {
        let expComponent = exp.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
        return "\(itemId)_\(expComponent)"
    }

    /// nil for a lot with no expiration date -- there's no "days until" a date that doesn't exist.
    var daysUntilExpiry: Int? {
        exp?.daysFromToday
    }

    /// Always false for a no-expiration lot: nothing with no expiration date can ever be "soon."
    var isExpiringSoon: Bool {
        guard let daysUntilExpiry else { return false }
        return daysUntilExpiry <= 14
    }
}
