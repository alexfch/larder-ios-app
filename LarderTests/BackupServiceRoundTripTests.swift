import XCTest
@testable import Larder

/// Extends the existing `BackupServiceTests` with the paths it doesn't cover: stock-take
/// adjustment transactions (signed qty + `reasonTag`) surviving an export/import round trip,
/// and the PRD's deliberate exclusion of count sessions from a backup (FR-5.3).
@MainActor
final class BackupServiceRoundTripTests: XCTestCase {
    var store: InMemoryCatalogStore!

    override func setUpWithError() throws {
        store = InMemoryCatalogStore()
    }

    func testAdjustmentTransactionsAndReasonTagsSurviveARoundTrip() throws {
        let flour = Item(name: "Flour", barcode: "3333333333333", kind: .bulk, unit: "g")
        try store.addItem(flour)
        try StockService.checkIn(itemId: flour.id, qty: 1000, exp: .now, store: store)
        try StockService.applyAdjustment(itemId: flour.id, delta: -150, reason: .spoiled, store: store)

        let exported = try BackupService.export(store: store)
        let freshStore = InMemoryCatalogStore()
        let summary = try BackupService.importBackup(exported, store: freshStore)

        XCTAssertEqual(summary.imported, 1)
        let restored = try XCTUnwrap(freshStore.item(matchingBarcode: "3333333333333"))
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: restored.id, transactions: freshStore.transactions), 850)

        let adjust = try XCTUnwrap(freshStore.transactions(for: restored.id).first { $0.action == .adjust })
        XCTAssertEqual(adjust.qty, -150, "the signed adjustment quantity is preserved")
        XCTAssertEqual(adjust.reasonTag, AdjustReason.spoiled.rawValue, "the reason tag is preserved")
    }

    func testItemsWithNoBarcodeAreBackedUpAndRestored() throws {
        // FR-5.3 / FR-4.2: multiple barcode-less items are legitimate and must round-trip.
        let leftovers = Item(name: "Leftover Curry", barcode: nil, kind: .unit, noun: "portion")
        let jam = Item(name: "Home-made Jam", barcode: nil, kind: .unit, noun: "jar")
        try store.addItem(leftovers)
        try store.addItem(jam)
        try StockService.checkIn(itemId: leftovers.id, qty: 2, exp: .now, store: store)
        try StockService.checkIn(itemId: jam.id, qty: 3, exp: .now, store: store)

        let exported = try BackupService.export(store: store)
        let freshStore = InMemoryCatalogStore()
        let summary = try BackupService.importBackup(exported, store: freshStore)

        XCTAssertEqual(summary.imported, 2)
        XCTAssertEqual(freshStore.items.count, 2)
    }

    func testCountSessionsAreNotIncludedInABackup() async throws {
        let beans = Item(name: "Beans", kind: .unit, noun: "tin")
        try store.addItem(beans)
        try StockService.checkIn(itemId: beans.id, qty: 5, exp: .now, store: store)
        _ = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: store.items, store: store)

        let exported = try BackupService.export(store: store)
        let decoded = try JSONDecoder.iso8601Decoder().decode(BackupPayload.self, from: exported)

        // The payload only carries items + their transactions — there is no field for sessions.
        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.items.first?.transactions.count, 1)
    }
}

private extension JSONDecoder {
    static func iso8601Decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
