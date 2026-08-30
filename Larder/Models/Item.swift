import Foundation

/// Firestore document shape for `/households/{householdId}/items/{itemId}` (ADR-0003): identity
/// fields only. No `onHandTotal`/`earliestBestBefore`/`lots` here — those are derived client-side
/// from `Transaction` documents by `CatalogDerivation`, not stored, since a stored running total
/// mutated in place would reintroduce exactly the cross-device write-conflict risk ADR-0003 exists
/// to avoid. See `CatalogStore` for how this and `Transaction` are kept in sync from Firestore.
struct Item: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var barcode: String?
    var kind: ItemKind
    /// Bulk-only: "g" or "ml"
    var unit: String?
    /// Unit-only: free-text noun, e.g. "tin", "jar", "egg"
    var noun: String?
    /// Cloud Storage for Firebase object path (ADR-0003) — not yet wired up; see `NewProductFormView`.
    var photoStorageRef: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        barcode: String? = nil,
        kind: ItemKind,
        unit: String? = nil,
        noun: String? = nil,
        photoStorageRef: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.barcode = barcode
        self.kind = kind
        self.unit = unit
        self.noun = noun
        self.photoStorageRef = photoStorageRef
        self.createdAt = createdAt
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
