import Foundation
import SwiftData

@Model
final class Item {
    var id: UUID
    var name: String
    var barcode: String?
    var kind: ItemKind
    /// Bulk-only: "g" or "ml"
    var unit: String?
    /// Unit-only: free-text noun, e.g. "tin", "jar", "egg"
    var noun: String?
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Lot.item)
    var lots: [Lot] = []

    @Relationship(deleteRule: .cascade, inverse: \Transaction.item)
    var transactions: [Transaction] = []

    init(
        id: UUID = UUID(),
        name: String,
        barcode: String? = nil,
        kind: ItemKind,
        unit: String? = nil,
        noun: String? = nil,
        photoData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.barcode = barcode
        self.kind = kind
        self.unit = unit
        self.noun = noun
        self.photoData = photoData
        self.createdAt = createdAt
    }

    var onHandTotal: Double {
        lots.reduce(0) { $0 + $1.qty }
    }

    var earliestBestBefore: Date? {
        lots.map(\.exp).min()
    }

    var sortedLots: [Lot] {
        lots.sorted { $0.exp < $1.exp }
    }

    var sortedTransactions: [Transaction] {
        transactions.sorted { $0.occurredAt > $1.occurredAt }
    }

    var monogram: String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    /// Formats a quantity per FR-2.3: whole units show an integer + pluralized noun,
    /// bulk items show g/ml below 1000 and roll up to kg/L (2 decimals) at or above it.
    func formattedQuantity(_ qty: Double) -> String {
        switch kind {
        case .unit:
            let count = Int(qty.rounded())
            let word = noun ?? "unit"
            let pluralized = count == 1 ? word : Self.pluralize(word)
            return "\(count) \(pluralized)"
        case .bulk:
            let baseUnit = unit ?? "g"
            if qty < 1000 {
                let formatted = qty == qty.rounded() ? String(Int(qty)) : String(format: "%.1f", qty)
                return "\(formatted) \(baseUnit)"
            } else {
                let rolledUp = qty / 1000
                let rolledUnit = baseUnit == "ml" ? "L" : "kg"
                return String(format: "%.2f %@", rolledUp, rolledUnit)
            }
        }
    }

    /// Single source of truth for barcode → catalog-item lookup. The architecture review flagged
    /// this as reimplemented independently at every scan site (Check In, Check Out, Count scan
    /// sweep, and the New Product duplicate-guard) — each as `allItems.first(where: { $0.barcode
    /// == code })`, a linear scan through a `@Query` that had to load the *entire* catalog into
    /// memory just to filter it in Swift. A predicate-backed `FetchDescriptor` with `fetchLimit =
    /// 1` lets SwiftData's store do the filtering instead, so a match costs one lookup regardless
    /// of catalog size, and the callers no longer need an unscoped `@Query` just for this.
    static func match(barcode: String, in context: ModelContext) -> Item? {
        var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.barcode == barcode })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func pluralize(_ word: String) -> String {
        guard let last = word.last else { return word }
        if "sxz".contains(last) || word.hasSuffix("ch") || word.hasSuffix("sh") {
            return word + "es"
        }
        if last == "y", word.count > 1 {
            let beforeLast = word[word.index(word.endIndex, offsetBy: -2)]
            if !"aeiou".contains(beforeLast) {
                return String(word.dropLast()) + "ies"
            }
        }
        return word + "s"
    }
}
