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
///   stored (see this struct's top-level doc comment) -- unless `allowsPartialCheckout` flips
///   that, see its own doc comment below.
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
    /// Packaged-only, requires `packageAmount`/`packageMeasurementUnit` to be set: whether an
    /// opened package can be checked out by weight/volume instead of only by the whole package
    /// (e.g. a 20 kg bag of flour you scoop from until it's empty). Checking a package *in* still
    /// always happens by the whole package -- only check-out switches to bulk terms -- but once
    /// this is true, the transaction log itself is written in bulk terms from that point on:
    /// checking in "1 bag" writes a `qty` of 20000, not 1. So `formattedQuantity`/
    /// `quantityUnitSuffix` treat this item's *stored* quantity as always bulk once this is true,
    /// with the package count demoted to a derived "≈ N bags" hint (`packageCountEquivalentText`)
    /// -- the mirror of the "(2.5 kg)" hint a non-partial packaged item shows. See
    /// `packageOpenStatus` for how "is a package currently open" is inferred from that stored
    /// quantity rather than tracked as its own state -- there's no per-physical-package identity,
    /// only how much of a package-equivalent remains unopened vs. open.
    var allowsPartialCheckout: Bool

    /// Non-packaged-only: whether this item is counted by individual unit or measured in bulk.
    /// Always nil for a `.packaged` item.
    var measurementStyle: MeasurementStyle?
    /// Non-packaged + counted-only: free-text name for one counted unit, e.g. "egg", "apple",
    /// "lemon". nil (falls back to "item") for a counted item with no more specific name.
    var countUnitName: String?
    /// Non-packaged + bulk-only: "g" | "kg" | "lb" | "ml" | "l" -- the unit this item's quantity
    /// is measured directly in.
    var bulkMeasurementUnit: String?

    /// Whether this product doesn't carry a best-before/expiration date at all (e.g. salt,
    /// cleaning supplies). When true, `NewProductFormView`'s Check In hand-off and
    /// `QuantitySheetView`'s own check-in both skip asking for a date entirely, and every batch
    /// checked in ends up with a nil `Lot`/`Transaction.exp` -- see those types' doc comments for
    /// what a nil `exp` means downstream.
    var noExpirationDate: Bool

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
        allowsPartialCheckout: Bool = false,
        measurementStyle: MeasurementStyle? = nil,
        countUnitName: String? = nil,
        bulkMeasurementUnit: String? = nil,
        noExpirationDate: Bool = false,
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
        self.allowsPartialCheckout = allowsPartialCheckout
        self.measurementStyle = measurementStyle
        self.countUnitName = countUnitName
        self.bulkMeasurementUnit = bulkMeasurementUnit
        self.noExpirationDate = noExpirationDate
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
    /// the +/- step size and whether the quantity field accepts decimals. Always true for
    /// `.packaged`, regardless of `allowsPartialCheckout` -- that flag only changes how check-*out*
    /// happens (see its doc comment); checking a package *in* is still always a whole-package
    /// count, which is what this property describes.
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
    /// 1000 and roll up to kg/L (2 decimals) at or above it. An `allowsPartialCheckout` packaged
    /// item flips this: its stored `qty` is already bulk terms, so the bulk amount is primary and
    /// the package count becomes the derived "(≈ N bags)" hint instead.
    func formattedQuantity(_ qty: Double) -> String {
        switch packaging {
        case .packaged:
            if allowsPartialCheckout, packageAmount != nil {
                let bulkText = Self.formattedBulkAmount(qty, unit: packageMeasurementUnit ?? "g")
                guard let countText = packageCountEquivalentText(for: qty) else { return bulkText }
                return "\(bulkText) (≈ \(countText))"
            }
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
    /// `formattedQuantity`'s combined string — `QuantitySheetView` uses this to preview the bulk
    /// total live while *checking in* an `allowsPartialCheckout` item (check-in is always
    /// package-count entry, so `qty` here means packages, same as any other packaged item). nil
    /// whenever there's no bulk equivalent to show (always the case for a non-packaged item).
    func packageBulkEquivalentText(for qty: Double) -> String? {
        guard packaging == .packaged, let packageAmount, let packageMeasurementUnit else { return nil }
        return Self.formattedBulkAmount(qty * packageAmount, unit: packageMeasurementUnit)
    }

    /// The reverse of `packageBulkEquivalentText`: how many packages a raw bulk amount is
    /// equivalent to (e.g. "0.7 bags" for 14 kg of a 20 kg-per-bag item). Used wherever a
    /// quantity is already in bulk terms rather than a package count -- an `allowsPartialCheckout`
    /// item's stored `qty`, or the amount being checked *out* of one in `QuantitySheetView`.
    func packageCountEquivalentText(for bulkQty: Double) -> String? {
        guard packaging == .packaged, let packageAmount, packageAmount > 0 else { return nil }
        let count = bulkQty / packageAmount
        let word = packageName ?? "unit"
        let pluralizedWord = count == 1 ? word : Self.pluralize(word)
        let formattedCount = count == count.rounded() ? String(Int(count)) : String(format: "%.2f", count)
        return "\(formattedCount) \(pluralizedWord)"
    }

    /// For an `allowsPartialCheckout` item, splits a raw stored quantity (bulk terms) into whole
    /// sealed packages plus whatever remains in a currently-open one. `openedAmount == 0` means
    /// every package this quantity represents is still sealed. nil for any item this doesn't
    /// apply to. "Open" is inferred purely from the numbers, per `allowsPartialCheckout`'s doc
    /// comment: once merged into one lot, individual physical packages aren't separately
    /// identifiable, only how much of a package-equivalent remains open.
    func packageOpenStatus(for qty: Double) -> (sealedPackages: Int, openedAmount: Double)? {
        guard packaging == .packaged, allowsPartialCheckout, let packageAmount, packageAmount > 0 else { return nil }
        let sealedPackages = Int((qty / packageAmount).rounded(.down))
        let openedAmount = qty - (Double(sealedPackages) * packageAmount)
        return (sealedPackages, openedAmount > 0.0001 ? openedAmount : 0)
    }

    /// "3 bags + 1 opened (2.5 kg)" -- nil when there's no open package to call out (every
    /// package in `qty` is still sealed, or this item doesn't support partial checkout at all).
    /// `ItemDetailView`'s per-batch rows use this in place of `formattedQuantity` so an opened
    /// batch reads as "opened" rather than just an odd-looking fractional bag count.
    func packageOpenStatusText(for qty: Double) -> String? {
        guard let status = packageOpenStatus(for: qty), status.openedAmount > 0 else { return nil }
        let word = packageName ?? "unit"
        let sealedWord = status.sealedPackages == 1 ? word : Self.pluralize(word)
        let openedText = Self.formattedBulkAmount(status.openedAmount, unit: packageMeasurementUnit ?? "g")
        return "\(status.sealedPackages) \(sealedWord) + 1 opened (\(openedText))"
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
    /// "counted in ___" label when called with `qty: 1` (e.g. `ItemDetailView`'s subtitle). An
    /// `allowsPartialCheckout` packaged item's *stored* quantity is always bulk terms, so this
    /// returns the bulk unit for it -- `QuantitySheetView`'s check-in flow, where the on-screen
    /// number is a package count instead, uses `packageCountSuffix` rather than this.
    func quantityUnitSuffix(for qty: Double) -> String {
        switch packaging {
        case .packaged:
            if allowsPartialCheckout, let packageMeasurementUnit {
                return packageMeasurementUnit
            }
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

    /// The package-name suffix alone (e.g. "bag"/"bags"), pluralized for `count` -- ignores
    /// `allowsPartialCheckout`, since checking a package *in* is always by whole package count
    /// even though its *stored* quantity switches to bulk terms afterward. `quantityUnitSuffix`
    /// is what every caller displaying a stored/on-hand quantity wants instead.
    func packageCountSuffix(for count: Double) -> String {
        let word = packageName ?? "unit"
        return Int(count.rounded()) == 1 ? word : Self.pluralize(word)
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
