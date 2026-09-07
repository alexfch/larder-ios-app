import XCTest
@testable import Larder

/// Phase 1 item 9 from the architecture review: a smoke-test performance ceiling at the PRD's
/// stated 5,000-item catalog target, so a change that turns a currently near-constant/linear-time
/// operation into an accidental O(n²) one fails a test instead of only surfacing later as a slow
/// app in the field.
///
/// Per the `swift-testing` skill's own migration boundary — "UI tests, performance benchmarks...
/// stay on XCTest" — this stays XCTest like the rest of the suite rather than introducing Swift
/// Testing for a single file. It also deliberately avoids XCTest's `measure()` baseline machinery:
/// an unconfigured `measure()` baseline records timing without ever failing a test on regression,
/// which wouldn't actually guard against one in a project with no CI to configure a baseline
/// against. A plain elapsed-time ceiling, generous enough not to flake on a slower machine, is the
/// simpler thing that actually enforces something.
///
/// Post-ADR-0003, these ceilings are generous specifically because `store.item(matchingBarcode:)`
/// and `CatalogDerivation`'s per-item lot math are now a client-side linear scan over an
/// already-synced array (no SwiftData predicate/index to do the filtering) — the honest cost of
/// moving persistence to Firestore. They're still expected to comfortably clear these ceilings at
/// the PRD's stated catalog cap; if they stop doing so, that's the "materialized/cached total"
/// follow-up ADR-0003 already calls out, not a bug in this test.
@MainActor
final class CatalogScalePerformanceTests: XCTestCase {
    var store: InMemoryCatalogStore!

    override func setUpWithError() throws {
        store = InMemoryCatalogStore()
    }

    @discardableResult
    private func makeCatalog(count: Int) throws -> [Item] {
        var items: [Item] = []
        items.reserveCapacity(count)
        for index in 0..<count {
            let item = Item(name: "Item \(index)", barcode: String(format: "%013d", index), packaging: .packaged, packageName: "tin")
            try store.addItem(item)
            try StockService.checkIn(itemId: item.id, qty: 3, exp: Date(timeIntervalSinceNow: Double(index) * 3600), store: store)
            items.append(item)
        }
        return items
    }

    func testBarcodeMatchStaysReasonablyFastAt5000Items() throws {
        let items = try makeCatalog(count: 5_000)
        let targetBarcode = try XCTUnwrap(items.last?.barcode)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = store.item(matchingBarcode: targetBarcode)
        }

        XCTAssertLessThan(elapsed, .seconds(1), "a single barcode lookup over the synced catalog should stay well under a second even as a linear scan")
    }

    func testExpirySortAndFilterStaysReasonablyFastAt5000Items() throws {
        let items = try makeCatalog(count: 5_000)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = CatalogFiltering.stockVisibleItems(items, transactions: store.transactions, expiringOnly: true)
        }

        XCTAssertLessThan(elapsed, .seconds(3), "filtering + sorting the full 5,000-item catalog by expiry should complete well under this ceiling")
    }

    func testStartSessionCompletesAt5000Items() async throws {
        let items = try makeCatalog(count: 5_000)

        let clock = ContinuousClock()
        let start = clock.now
        _ = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: items, store: store)
        let elapsed = clock.now - start

        XCTAssertLessThan(elapsed, .seconds(5), "starting a stock-take session against the full catalog should complete in a few seconds, not hang")
    }
}
