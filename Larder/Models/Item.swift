import Foundation

/// Firestore document shape for `/households/{householdId}/items/{itemId}` (ADR-0003): identity
/// fields only. No `onHandTotal`/`earliestBestBefore`/`lots` here — those are derived client-side
/// from `Transaction` documents by `CatalogDerivation`, not stored, since a stored running total
/// mutated in place would reintroduce exactly the cross-device write-conflict risk ADR-0003 exists
/// to avoid. See `CatalogStore` for how this and `Transaction` are kept in sync from Firestore.
///
/// `packaging` splits every item into one of three shapes, mirroring the three-way choice on
/// `NewProductFormView`:
/// - **Packaged** (`.packaged`): tracked by whole package count (e.g. "5 jars"), optionally with
///   a known bulk size per package (e.g. a 500 g pack of spaghetti) so the on-hand total can also
///   show its bulk equivalent (e.g. "5 packs (2.5 kg)"). The transaction log still records whole
///   packages exactly as before; the bulk equivalent is a purely derived display computed from
///   that count, never its own stored total, for the same reason `onHandTotal` itself isn't
///   stored (see this struct's top-level doc comment).
/// - **Non-packaged, counted** (`.nonPackaged` + `measurementStyle == .count`): tracked by whole
///   individually-counted units with no package around them (e.g. "3 eggs").
/// - **Non-packaged, bulk** (`.nonPackaged` + `measurementStyle == .bulk`): tracked directly in
///   weight/volume with no whole-unit count at all (e.g. "750 g" of loose flour).
struct Item: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var barcode: String?
    var packaging: PackagingType

    /// Packaged-only: free-text name for one package, e.g. "jar", "tin", "pack". nil (falls back
    /// to "unit") for a packaged item with no more specific name.
    var packageName: String?
    /// Packaged-only, both optional together with `packageMeasurementUnit`: how much bulk one
    /// single package contains, e.g. 500 for a 500 g pack of spaghetti. nil for a packaged item
    /// with no known bulk size (e.g. a jar of pickles bought by the jar, not by weight).
    var packageAmount: Double?
    /// Packaged-only: "g" | "kg" | "lb" | "ml" | "l" -- the unit `packageAmount` is measured in.
    var packageMeasurementUnit: String?

    /// Non-packaged-only: whether this item is counted by individual unit or measured in bulk.
    /// Always nil for a `.packaged` item.
    var measurementStyle: MeasurementStyle?
    /// Non-packaged + counted-only: free-text name for one counted unit, e.g. "egg", "apple",
    /// "lemon". nil (falls back to "item") for a counted item with no more specific name.
    var countUnitName: String?
    /// Non-packaged + bulk-only: "g" | "kg" | "lb" | "ml" | "l" -- the unit this item's quantity
    /// is measured directly in.
    var bulkMeasurementUnit: String?

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
        packaging: PackagingType,
        packageName: String? = nil,
        packageAmount: Double? = nil,
        packageMeasurementUnit: String? = nil,
        measurementStyle: MeasurementStyle? = nil,
        countUnitName: String? = nil,
        bulkMeasurementUnit: String? = nil,
        photoStorageRef: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.barcode = barcode
        self.packaging = packaging
        self.packageName = packageName
        self.packageAmount = packageAmount
        self.packageMeasurementUnit = packageMeasurementUnit
        self.measurementStyle = measurementStyle
        self.countUnitName = countUnitName
        self.bulkMeasurementUnit = bulkMeasurementUnit
        self.photoStorageRef = photoStorageRef
        self.createdAt = createdAt
    }

    var monogram: String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    /// Whether this item's quantity is tracked as whole counted units (packages, or individually
    /// counted loose items like eggs) rather than continuous weight/volume. Drives things like
    /// the +/- step size and whether the quantity field accepts decimals.
    var isCountedInWholeUnits: Bool {
        switch packaging {
        case .packaged: return true
        case .nonPackaged: return (measurementStyle ?? .bulk) == .count
        }
    }

    /// The unit this item's quantity is measured directly in when it's *not* tracked as whole
    /// units -- nil for a packaged or counted item, since those track whole units instead.
    var continuousMeasurementUnit: String? {
        guard packaging == .nonPackaged, (measurementStyle ?? .bulk) == .bulk else { return nil }
        return bulkMeasurementUnit
    }

    /// Formats a quantity per FR-2.3: whole packages/units show an integer + pluralized name,
    /// packaged items optionally followed by their bulk equivalent when `packageAmount`/
    /// `packageMeasurementUnit` are set (e.g. "5 packs (2.5 kg)"); bulk items show g/ml below
    /// 1000 and roll up to kg/L (2 decimals) at or above it.
    func formattedQuantity(_ qty: Double) -> String {
        switch packaging {
        case .packaged:
            let count = Int(qty.rounded())
            let word = packageName ?? "unit"
            let pluralized = count == 1 ? word : Self.pluralize(word)
            var result = "\(count) \(pluralized)"
            if let bulkTotal = packageBulkEquivalentText(for: qty) {
                result += " (\(bulkTotal))"
            }
            return result
        case .nonPackaged:
            switch measurementStyle ?? .bulk {
            case .count:
                let count = Int(qty.rounded())
                let word = countUnitName ?? "item"
                let pluralized = count == 1 ? word : Self.pluralize(word)
                return "\(count) \(pluralized)"
            case .bulk:
                return Self.formattedBulkAmount(qty, unit: bulkMeasurementUnit ?? "g")
            }
        }
    }

    /// The bulk-equivalent total alone (e.g. "2.5 kg" for 5 packs of a 500 g item), for a caller
    /// that wants to show it separately from the pack count rather than as part of
    /// `formattedQuantity`'s combined string — `QuantitySheetView` uses this to update the total
    /// live as the pack count changes. nil whenever there's no bulk equivalent to show (always
    /// the case for a non-packaged item).
    func packageBulkEquivalentText(for qty: Double) -> String? {
        guard packaging == .packaged, let packageAmount, let packageMeasurementUnit else { return nil }
        return Self.formattedBulkAmount(qty * packageAmount, unit: packageMeasurementUnit)
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

    /// The unit/name suffix alone, in the same base-unit terms `formattedQuantity` uses below the
    /// 1000-gram/mL rollup threshold — for an editable quantity field, where the typed number has
    /// to map 1:1 to the stored value. Unlike `formattedQuantity`, this never rolls a bulk
    /// quantity up to kg/L: doing so would silently change what a typed number means (typing
    /// "1500" next to a "kg" label would mean 1500 kg, not 1500 g). Also doubles as a singular
    /// "counted in ___" label when called with `qty: 1` (e.g. `ItemDetailView`'s subtitle).
    func quantityUnitSuffix(for qty: Double) -> String {
        switch packaging {
        case .packaged:
            let count = Int(qty.rounded())
            let word = packageName ?? "unit"
            return count == 1 ? word : Self.pluralize(word)
        case .nonPackaged:
            switch measurementStyle ?? .bulk {
            case .count:
                let count = Int(qty.rounded())
                let word = countUnitName ?? "item"
                return count == 1 ? word : Self.pluralize(word)
            case .bulk:
                return bulkMeasurementUnit ?? "g"
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
