import XCTest
import SwiftData
@testable import Larder

final class BackupServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Item.self, Lot.self, Transaction.self, CountSession.self, CountLine.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    func testExportThenImportIntoAFreshStoreRestoresTheCatalog() throws {
        let beans = Item(name: "Beans", barcode: "1111111111111", kind: .unit, noun: "tin")
        context.insert(beans)
        StockService.checkIn(item: beans, qty: 5, exp: .now, context: context)
        try StockService.checkOut(item: beans, qty: 2, context: context)

        let exported = try BackupService.export(context: context)

        // A fresh store, as if restoring onto a new install.
        let freshContainer = try ModelContainer(for: Schema([Item.self, Lot.self, Transaction.self, CountSession.self, CountLine.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let freshContext = ModelContext(freshContainer)

        let summary = try BackupService.importBackup(exported, context: freshContext)

        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.skippedAlreadyPresent, 0)
        XCTAssertEqual(summary.skippedBarcodeConflict, 0)

        let restored = try XCTUnwrap(Item.match(barcode: "1111111111111", in: freshContext))
        XCTAssertEqual(restored.name, "Beans")
        XCTAssertEqual(restored.onHandTotal, 3, "check-in minus check-out, preserved from the original")
        XCTAssertEqual(restored.transactions.count, 2, "both the check-in and check-out transactions restored")
    }

    func testImportSkipsAnItemAlreadyPresentByID() throws {
        let beans = Item(name: "Beans", kind: .unit, noun: "tin")
        context.insert(beans)
        StockService.checkIn(item: beans, qty: 5, exp: .now, context: context)

        let exported = try BackupService.export(context: context)

        // Re-importing into the SAME store the backup was taken from must not duplicate it.
        let summary = try BackupService.importBackup(exported, context: context)

        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.skippedAlreadyPresent, 1)
        let allItems = try context.fetch(FetchDescriptor<Item>())
        XCTAssertEqual(allItems.count, 1, "no duplicate item created")
    }

    func testImportSkipsABarcodeConflictWithoutOverwritingTheExistingItem() throws {
        // Export an item with a given barcode...
        let original = Item(name: "Beans", barcode: "2222222222222", kind: .unit, noun: "tin")
        context.insert(original)
        StockService.checkIn(item: original, qty: 5, exp: .now, context: context)
        let exported = try BackupService.export(context: context)

        // ...then import into a store that already has a DIFFERENT item using that same barcode
        // (different id, e.g. re-added by hand after the original backup was taken).
        let freshContainer = try ModelContainer(for: Schema([Item.self, Lot.self, Transaction.self, CountSession.self, CountLine.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let freshContext = ModelContext(freshContainer)
        let conflicting = Item(name: "Different Beans", barcode: "2222222222222", kind: .unit, noun: "tin")
        freshContext.insert(conflicting)
        StockService.checkIn(item: conflicting, qty: 9, exp: .now, context: freshContext)

        let summary = try BackupService.importBackup(exported, context: freshContext)

        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.skippedBarcodeConflict, 1)
        let survivor = try XCTUnwrap(Item.match(barcode: "2222222222222", in: freshContext))
        XCTAssertEqual(survivor.name, "Different Beans", "the existing item must not be overwritten by the import")
        XCTAssertEqual(survivor.onHandTotal, 9)
    }

    func testImportRejectsANewerUnsupportedFormatVersion() throws {
        let payload = BackupPayload(formatVersion: BackupPayload.currentFormatVersion + 1, exportedAt: .now, items: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        XCTAssertThrowsError(try BackupService.importBackup(data, context: context)) { error in
            XCTAssertTrue(error is BackupServiceError)
        }
    }
}
