import Foundation

// MARK: - DTOs

/// JSON shape for a Larder backup. Deliberately scoped, per the architecture review's caution
/// that "whatever ships to close this gap introduces a new data-exposure surface": covers the
/// catalog (`Item` → `Transaction`, the actual pantry state and its full history) and nothing else.
///
/// - `CountSession`/`CountLine` are excluded: a stock-take session is workflow state tied to a
///   point in time, not pantry data — an applied session's effect already lives on in the
///   `Transaction` history it wrote, and an in-progress or discarded session has nothing worth
///   restoring independently of the catalog it was counting.
/// - Photos are excluded, per the PRD's already-resolved FR-5.3 decision: they'd roughly double
///   the export size for something easy to reattach by hand if truly needed, and are the most
///   personal part of this data. Only `photoStorageRef` (a Cloud Storage path, not the photo
///   itself) would need to round-trip through this format anyway, and a restored item without a
///   photo is a strictly better outcome than one pointing at an object that was never re-uploaded.
/// - No encryption: this is non-financial, non-credential data (item names, quantities, dates)
///   — it doesn't meet the bar this app's actual secrets (there are none yet) would need
///   Keychain/CryptoKit for. The real exposure this format doesn't defend against is the
///   *destination* the user picks in the system export/import pickers (e.g. an unencrypted cloud
///   drive) — squarely the user's own choice.
struct BackupPayload: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let exportedAt: Date
    let items: [BackupItem]
}

struct BackupItem: Codable {
    let id: String
    let name: String
    let barcode: String?
    let kind: ItemKind
    let unit: String?
    let noun: String?
    let createdAt: Date
    let transactions: [BackupTransaction]
}

struct BackupTransaction: Codable {
    let id: String
    let action: TransactionAction
    let qty: Double
    let exp: Date
    let occurredAt: Date
    let reasonTag: String?
}

struct BackupImportSummary {
    let imported: Int
    let skippedAlreadyPresent: Int
    let skippedBarcodeConflict: Int
}

enum BackupServiceError: LocalizedError {
    case unsupportedFormatVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormatVersion(let version):
            return "This backup was made with a newer version of Larder (format \(version)) and can't be read by this version."
        }
    }
}

/// Exports/imports the catalog as JSON for local backup, per the PRD's stated backup/export NFR.
/// Reads/writes through `CatalogStore`'s already-synced local arrays rather than a `ModelContext`
/// fetch, now that the catalog lives in Firestore (ADR-0003). See `BackupPayload`'s doc comment
/// for what's deliberately in and out of scope.
enum BackupService {

    @MainActor
    static func export(store: CatalogWriting) throws -> Data {
        let backupItems = store.items.sorted { $0.name < $1.name }.map { item in
            BackupItem(
                id: item.id,
                name: item.name,
                barcode: item.barcode,
                kind: item.kind,
                unit: item.unit,
                noun: item.noun,
                createdAt: item.createdAt,
                transactions: store.transactions(for: item.id).map {
                    BackupTransaction(
                        id: $0.id,
                        action: $0.action,
                        qty: $0.qty,
                        exp: $0.exp,
                        occurredAt: $0.occurredAt,
                        reasonTag: $0.reasonTag
                    )
                }
            )
        }

        let payload = BackupPayload(
            formatVersion: BackupPayload.currentFormatVersion,
            exportedAt: .now,
            items: backupItems
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// Recreates items from a backup, skipping (not overwriting) anything that already looks
    /// present — either the same `id` (this exact backup, or part of it, was already imported) or
    /// a colliding non-empty `barcode` on a *different* item, which would otherwise violate the
    /// barcode-uniqueness invariant documented in ADR-0001. A skip never mutates the existing
    /// item; restoring over live data always favors what's already there.
    @MainActor
    static func importBackup(_ data: Data, store: CatalogWriting) throws -> BackupImportSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)

        guard payload.formatVersion <= BackupPayload.currentFormatVersion else {
            throw BackupServiceError.unsupportedFormatVersion(payload.formatVersion)
        }

        var imported = 0
        var skippedAlreadyPresent = 0
        var skippedBarcodeConflict = 0

        for backupItem in payload.items {
            if store.item(id: backupItem.id) != nil {
                skippedAlreadyPresent += 1
                continue
            }
            if let barcode = backupItem.barcode, !barcode.isEmpty, store.item(matchingBarcode: barcode) != nil {
                skippedBarcodeConflict += 1
                continue
            }

            let item = Item(
                id: backupItem.id,
                name: backupItem.name,
                barcode: backupItem.barcode,
                kind: backupItem.kind,
                unit: backupItem.unit,
                noun: backupItem.noun,
                createdAt: backupItem.createdAt
            )
            try store.addItem(item)

            for backupTransaction in backupItem.transactions {
                let transaction = Transaction(
                    id: backupTransaction.id,
                    itemId: item.id,
                    action: backupTransaction.action,
                    qty: backupTransaction.qty,
                    exp: backupTransaction.exp,
                    occurredAt: backupTransaction.occurredAt,
                    reasonTag: backupTransaction.reasonTag
                )
                try store.addTransaction(transaction)
            }

            imported += 1
        }

        return BackupImportSummary(
            imported: imported,
            skippedAlreadyPresent: skippedAlreadyPresent,
            skippedBarcodeConflict: skippedBarcodeConflict
        )
    }
}
