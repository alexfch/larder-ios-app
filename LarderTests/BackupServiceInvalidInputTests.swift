import XCTest
@testable import Larder

/// FR-5.3 acceptance criterion 4: "Given the selected file is not a valid Larder backup, or was
/// exported by a newer version of the app than the one importing it, then the import fails with
/// a clear error rather than partially importing or corrupting existing data."
///
/// `BackupServiceTests` covers the newer-format-version case and the happy-path round trip; this
/// file covers malformed input and confirms a failed import leaves the store untouched.
@MainActor
final class BackupServiceInvalidInputTests: XCTestCase {
    var store: InMemoryCatalogStore!

    override func setUpWithError() throws {
        store = InMemoryCatalogStore()
    }

    func testImportingBytesThatAreNotJSONThrowsAndChangesNothing() throws {
        let existing = Item(name: "Beans", barcode: "1111111111111", kind: .unit, noun: "tin")
        try store.addItem(existing)
        try StockService.checkIn(itemId: existing.id, qty: 4, exp: .now, store: store)

        let garbage = Data("this is not a backup file".utf8)

        XCTAssertThrowsError(try BackupService.importBackup(garbage, store: store))
        XCTAssertEqual(store.items.count, 1, "the existing catalog is untouched by a failed import")
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: existing.id, transactions: store.transactions), 4)
    }

    func testImportingWellFormedJSONThatIsNotABackupPayloadThrows() throws {
        let unrelatedJSON = Data(#"{"hello":"world","count":3}"#.utf8)

        XCTAssertThrowsError(try BackupService.importBackup(unrelatedJSON, store: store))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testEmptyBackupImportsCleanlyAsZeroItems() throws {
        let payload = BackupPayload(formatVersion: BackupPayload.currentFormatVersion, exportedAt: .now, items: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let summary = try BackupService.importBackup(data, store: store)

        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.skippedAlreadyPresent, 0)
        XCTAssertEqual(summary.skippedBarcodeConflict, 0)
    }

    func testExportedTransactionsSurviveAFullRoundTripWithTheirActionsAndReasonsIntact() throws {
        let beans = Item(name: "Beans", kind: .unit, noun: "tin")
        try store.addItem(beans)
        try StockService.checkIn(itemId: beans.id, qty: 10, exp: .now, store: store)
        try StockService.checkOut(itemId: beans.id, qty: 2, store: store)
        try StockService.applyAdjustment(itemId: beans.id, delta: -1, reason: .spoiled, store: store)

        let exported = try BackupService.export(store: store)
        let fresh = InMemoryCatalogStore()
        _ = try BackupService.importBackup(exported, store: fresh)

        let restored = try XCTUnwrap(fresh.items.first)
        let actions = fresh.transactions(for: restored.id).map(\.action)
        XCTAssertEqual(Set(actions), [.checkIn, .checkOut, .adjust])
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: restored.id, transactions: fresh.transactions), 7, "10 − 2 − 1")
        let adjust = try XCTUnwrap(fresh.transactions(for: restored.id).first { $0.action == .adjust })
        XCTAssertEqual(adjust.reasonTag, AdjustReason.spoiled.rawValue)
    }
}
