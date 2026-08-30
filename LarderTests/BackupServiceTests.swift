import XCTest
@testable import Larder

@MainActor
final class BackupServiceTests: XCTestCase {
    var store: InMemoryCatalogStore!

    override func setUpWithError() throws {
        store = InMemoryCatalogStore()
    }

    private func onHandTotal(_ store: InMemoryCatalogStore, itemId: String) -> Double {
        CatalogDerivation.onHandTotal(itemId: itemId, transactions: store.transactions)
    }

    func testExportThenImportIntoAFreshStoreRestoresTheCatalog() throws {
        let beans = Item(name: "Beans", barcode: "1111111111111", kind: .unit, noun: "tin")
        try store.addItem(beans)
        try StockService.checkIn(itemId: beans.id, qty: 5, exp: .now, store: store)
        try StockService.checkOut(itemId: beans.id, qty: 2, store: store)

        let exported = try BackupService.export(store: store)

        // A fresh store, as if restoring onto a new install.
        let freshStore = InMemoryCatalogStore()

        let summary = try BackupService.importBackup(exported, store: freshStore)

        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.skippedAlreadyPresent, 0)
        XCTAssertEqual(summary.skippedBarcodeConflict, 0)

        let restored = try XCTUnwrap(freshStore.item(matchingBarcode: "1111111111111"))
        XCTAssertEqual(restored.name, "Beans")
        XCTAssertEqual(onHandTotal(freshStore, itemId: restored.id), 3, "check-in minus check-out, preserved from the original")
        XCTAssertEqual(freshStore.transactions(for: restored.id).count, 2, "both the check-in and check-out transactions restored")
    }

    func testImportSkipsAnItemAlreadyPresentByID() throws {
        let beans = Item(name: "Beans", kind: .unit, noun: "tin")
        try store.addItem(beans)
        try StockService.checkIn(itemId: beans.id, qty: 5, exp: .now, store: store)

        let exported = try BackupService.export(store: store)

        // Re-importing into the SAME store the backup was taken from must not duplicate it.
        let summary = try BackupService.importBackup(exported, store: store)

        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.skippedAlreadyPresent, 1)
        XCTAssertEqual(store.items.count, 1, "no duplicate item created")
    }

    func testImportSkipsABarcodeConflictWithoutOverwritingTheExistingItem() throws {
        // Export an item with a given barcode...
        let original = Item(name: "Beans", barcode: "2222222222222", kind: .unit, noun: "tin")
        try store.addItem(original)
        try StockService.checkIn(itemId: original.id, qty: 5, exp: .now, store: store)
        let exported = try BackupService.export(store: store)

        // ...then import into a store that already has a DIFFERENT item using that same barcode
        // (different id, e.g. re-added by hand after the original backup was taken).
        let freshStore = InMemoryCatalogStore()
        let conflicting = Item(name: "Different Beans", barcode: "2222222222222", kind: .unit, noun: "tin")
        try freshStore.addItem(conflicting)
        try StockService.checkIn(itemId: conflicting.id, qty: 9, exp: .now, store: freshStore)

        let summary = try BackupService.importBackup(exported, store: freshStore)

        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.skippedBarcodeConflict, 1)
        let survivor = try XCTUnwrap(freshStore.item(matchingBarcode: "2222222222222"))
        XCTAssertEqual(survivor.name, "Different Beans", "the existing item must not be overwritten by the import")
        XCTAssertEqual(onHandTotal(freshStore, itemId: survivor.id), 9)
    }

    func testImportRejectsANewerUnsupportedFormatVersion() throws {
        let payload = BackupPayload(formatVersion: BackupPayload.currentFormatVersion + 1, exportedAt: .now, items: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        XCTAssertThrowsError(try BackupService.importBackup(data, store: store)) { error in
            XCTAssertTrue(error is BackupServiceError)
        }
    }
}
