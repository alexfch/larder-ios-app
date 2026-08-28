import Foundation
import SwiftData

// MARK: - DTOs

/// JSON shape for a Larder backup. Deliberately scoped, per the architecture review's caution
/// that "whatever ships to close this gap introduces a new data-exposure surface": covers the
/// catalog (`Item` → `Lot` → `Transaction`, the actual pantry state and its full history) and
/// nothing else.
///
/// - `CountSession`/`CountLine` are excluded: a stock-take session is workflow state tied to a
///   point in time, not pantry data — an applied session's effect already lives on in the
///   `Transaction` history it wrote, and an in-progress or discarded session has nothing worth
///   restoring independently of the catalog it was counting.
/// - `Item.photoData` is excluded: photos are the most personal part of this data (a picture of
///   someone's kitchen can incidentally capture more than the product in frame) and roughly
///   double the export's size for something the restore flow doesn't strictly need back.
/// - No encryption: this is non-financial, non-credential data (item names, quantities, dates)
///   local to a solo-developer app with no accounts or backend — it doesn't meet the bar this
///   app's actual secrets (there are none yet) would need Keychain/CryptoKit for. The real
///   exposure this format doesn't defend against is the *destination* the user picks in the
///   system export/import pickers (e.g. an unencrypted cloud drive) — squarely the user's own
///   choice, not something client-side encryption of the file itself would meaningfully change
///   without also solving key management and recovery, which would be disproportionate to what
///   this feature needs to do. Revisit if the app ever stores anything encryption would actually
///   protect (accounts, PIN-gated data per the PRD's Phase 2).
struct BackupPayload: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let exportedAt: Date
    let items: [BackupItem]
}

struct BackupItem: Codable {
    let id: UUID
    let name: String
    let barcode: String?
    let kind: ItemKind
    let unit: String?
    let noun: String?
    let createdAt: Date
    let lots: [BackupLot]
    let transactions: [BackupTransaction]
}

struct BackupLot: Codable {
    let id: UUID
    let qty: Double
    let exp: Date
}

struct BackupTransaction: Codable {
    let id: UUID
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

/// Exports/imports the catalog as JSON for local backup, per the PRD's stated (but previously
/// unbuilt) backup/export NFR. See `BackupPayload`'s doc comment for what's deliberately in and
/// out of scope.
enum BackupService {

    static func export(context: ModelContext) throws -> Data {
        let items = try context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.name)]))

        let backupItems = items.map { item in
            BackupItem(
                id: item.id,
                name: item.name,
                barcode: item.barcode,
                kind: item.kind,
                unit: item.unit,
                noun: item.noun,
                createdAt: item.createdAt,
                lots: item.lots.map { BackupLot(id: $0.id, qty: $0.qty, exp: $0.exp) },
                transactions: item.transactions.map {
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
    static func importBackup(_ data: Data, context: ModelContext) throws -> BackupImportSummary {
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
            if existingItem(id: backupItem.id, in: context) != nil {
                skippedAlreadyPresent += 1
                continue
            }
            if let barcode = backupItem.barcode, !barcode.isEmpty, Item.match(barcode: barcode, in: context) != nil {
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
            context.insert(item)

            for backupLot in backupItem.lots {
                let lot = Lot(id: backupLot.id, item: item, qty: backupLot.qty, exp: backupLot.exp)
                context.insert(lot)
            }
            for backupTransaction in backupItem.transactions {
                let transaction = Transaction(
                    id: backupTransaction.id,
                    item: item,
                    action: backupTransaction.action,
                    qty: backupTransaction.qty,
                    exp: backupTransaction.exp,
                    occurredAt: backupTransaction.occurredAt,
                    reasonTag: backupTransaction.reasonTag
                )
                context.insert(transaction)
            }

            imported += 1
        }

        return BackupImportSummary(
            imported: imported,
            skippedAlreadyPresent: skippedAlreadyPresent,
            skippedBarcodeConflict: skippedBarcodeConflict
        )
    }

    private static func existingItem(id: UUID, in context: ModelContext) -> Item? {
        var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
