import Foundation

/// A "batch" of one item dated to one best-before date. No longer a stored Firestore document
/// (ADR-0003) — it's a derived grouping of that item's `Transaction` documents sharing an `exp`
/// date, computed by `CatalogDerivation`, exactly mirroring what the old SwiftData `Lot` entity
/// represented but without any field a second device could ever conflict-write.
struct Lot: Identifiable, Hashable {
    var itemId: String
    var qty: Double
    var exp: Date

    var id: String { "\(itemId)_\(Int(exp.timeIntervalSince1970))" }

    var daysUntilExpiry: Int {
        exp.daysFromToday
    }

    var isExpiringSoon: Bool {
        daysUntilExpiry <= 14
    }
}
