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
    /// Unit-only, both optional together: how much bulk one single unit/pack contains (e.g. a
    /// 500 g pack of spaghetti) — lets a packaged product's on-hand total show its bulk
    /// equivalent (e.g. "5 packs (2.5 kg)") without changing how check-in/check-out work at all.
    /// The transaction log still records whole packs exactly as it always has for `.unit` items;
    /// this is a purely derived display computed from that count, never its own stored total, for
    /// the same reason `onHandTotal` itself isn't stored (see this struct's top-level doc
    /// comment). nil for a unit item with no known pack size (e.g. eggs), and always nil for
    /// `.bulk` items, which are already tracked directly in bulk terms.
    var bulkEquivalentAmount: Double?
    /// "g" | "kg" | "lbs" | "ml" | "l" -- same vocabulary as the existing bulk `unit` field.
    var bulkEquivalentUnit: String?
    /// Cloud Storage for Firebase object path (ADR-0003, Phase 2) — set by `NewProductFormView`
    /// at save time, once `PhotoStorage.upload` has confirmed the object exists; nil for an item
    /// with no photo. See `storage.rules` for the matching access rule and `ItemThumbnail` for
    /// how this gets fetched and displayed.
    var photoStorageRef: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        barcode: String? = nil,
        kind: ItemKind,
        unit: String? = nil,
        noun: String? = nil,
        bulkEquivalentAmount: Double? = nil,
        bulkEquivalentUnit: String? = nil,
        photoStorageRef: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.barcode = barcode
        self.kind = kind
        self.unit = unit
        self.noun = noun
        self.bulkEquivalentAmount = bulkEquivalentAmount
        self.bulkEquivalentUnit = bulkEquivalentUnit
        self.photoStorageRef = photoStorageRef
        self.createdAt = createdAt
    }

    var monogram: String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    /// Formats a quantity per FR-2.3: whole units show an integer + pluralized noun, optionally
    /// followed by its bulk equivalent when `bulkEquivalentAmount`/`bulkEquivalentUnit` are set
    /// (e.g. "5 packs (2.5 kg)"); bulk items show g/ml below 1000 and roll up to kg/L (2 decimals)
    /// at or above it.
    func formattedQuantity(_ qty: Double) -> String {
        switch kind {
        case .unit:
            let count = Int(qty.rounded())
            let word = noun ?? "unit"
            let pluralized = count == 1 ? word : Self.pluralize(word)
            var result = "\(count) \(pluralized)"
            if let bulkTotal = bulkEquivalentText(for: qty) {
                result += " (\(bulkTotal))"
            }
            return result
        case .bulk:
            return Self.formattedBulkAmount(qty, unit: unit ?? "g")
        }
    }

    /// The bulk-equivalent total alone (e.g. "2.5 kg" for 5 packs of a 500 g item), for a caller
    /// that wants to show it separately from the pack count rather than as part of
    /// `formattedQuantity`'s combined string — `QuantitySheetView` uses this to update the total
    /// live as the pack count changes. nil whenever there's no bulk equivalent to show.
    func bulkEquivalentText(for qty: Double) -> String? {
        guard kind == .unit, let bulkEquivalentAmount, let bulkEquivalentUnit else { return nil }
        return Self.formattedBulkAmount(qty * bulkEquivalentAmount, unit: bulkEquivalentUnit)
    }

    private static func formattedBulkAmount(_ amount: Double, unit: String) -> String {
        if amount < 1000 {
            let formatted = amount == amount.rounded() ? String(Int(amount)) : String(format: "%.1f", amount)
            return "\(formatted) \(unit)"
        } else {
            let rolledUp = amount / 1000
            let rolledUnit = unit == "ml" ? "L" : "kg"
            return String(format: "%.2f %@", rolledUp, rolledUnit)
        }
    }

    /// The unit/noun suffix alone, in the same base-unit terms `formattedQuantity` uses below the
    /// 1000-gram/mL rollup threshold — for an editable quantity field, where the typed number has
    /// to map 1:1 to the stored value. Unlike `formattedQuantity`, this never rolls a bulk
    /// quantity up to kg/L: doing so would silently change what a typed number means (typing
    /// "1500" next to a "kg" label would mean 1500 kg, not 1500 g).
    func quantityUnitSuffix(for qty: Double) -> String {
        switch kind {
        case .unit:
            let count = Int(qty.rounded())
            let word = noun ?? "unit"
            return count == 1 ? word : Self.pluralize(word)
        case .bulk:
            return unit ?? "g"
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
