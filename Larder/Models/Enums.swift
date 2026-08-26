import Foundation

enum ItemKind: String, Codable, CaseIterable {
    case unit
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
