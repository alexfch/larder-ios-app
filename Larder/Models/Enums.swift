import Foundation

/// Whether a product is bought/tracked as pre-measured packages (e.g. a 500 g bag of pasta,
/// sold as "1 pack") or as a non-packaged product measured directly at check-in/out time --
/// either by counting individual items (eggs, apples) or by weight/volume (loose rice, olive
/// oil). Mirrors the "packaged" / "non-packaged" choice on `NewProductFormView`.
enum PackagingType: String, Codable, CaseIterable {
    case packaged
    case nonPackaged
}

/// For a `.nonPackaged` item only: whether its quantity is tracked by counting individual units
/// or by weight/volume. Meaningless (and always nil on `Item`) for a `.packaged` item, which is
/// always counted in whole packages regardless of what's inside one. Mirrors the "Measure by"
/// choice on `NewProductFormView`.
enum MeasurementStyle: String, Codable, CaseIterable {
    case count
    case bulk
}

enum TransactionAction: String, Codable {
    case checkIn = "IN"
    case checkOut = "OUT"
    case adjust = "ADJUST"
}

enum AdjustReason: String, Codable, CaseIterable, Identifiable {
    case used = "Used"
    case spoiled = "Spoiled"
    case miscount = "Miscount"
    case givenAway = "Given away"

    var id: String { rawValue }
}

enum CountMode: String, Codable, CaseIterable {
    case checklist
    case scanSweep
}

enum CountStatus: String, Codable {
    case inProgress
    case applied
    case discarded
}
