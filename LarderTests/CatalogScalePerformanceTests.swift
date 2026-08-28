import XCTest
import SwiftData
@testable import Larder

/// Phase 1 item 9 from the architecture review: a smoke-test performance ceiling at the PRD's
/// stated 5,000-item catalog target, so a change that turns a currently near-constant-time
/// operation into an accidental O(n) or O(n²) one fails a test instead of only surfacing later as
/// a slow app in the field.
///
/// Per the `swift-testing` skill's own migration boundary — "UI tests, performance benchmarks...
/// stay on XCTest" — this stays XCTest like the rest of the suite rather than introducing Swift
/// Testing for a single file. It also deliberately avoids XCTest's `measure()` baseline machinery:
/// an unconfigured `measure()` baseline records timing without ever failing a test on regression,
/// which wouldn't actually guard against one in a project with no CI to configure a baseline
/// against. A plain elapsed-time ceiling, generous enough not to flake on a slower machine, is the
/// simpler thing that actually enforces something.
final class CatalogScalePerformanceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Item.self, Lot.self, Transaction.self, CountSession.self, CountLine.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    @discardableResult
    private func makeCatalog(count: Int) -> [Item] {
        var items: [Item] = []
        items.reserveCapacity(count)
        for index in 0..<count {
            let item = Item(name: "Item \(index)", barcode: String(format: "%013d", index), kind: .unit, noun: "tin")
            context.insert(item)
            let lot = Lot(item: item, qty: 3, exp: Date(timeIntervalSinceNow: Double(index) * 3600))
            context.insert(lot)
            item.lots.append(lot)
            items.append(item)
        }
        return items
    }

    func testBarcodeMatchStaysFastAt5000Items() throws {
        let items = makeCatalog(count: 5_000)
        let targetBarcode = try XCTUnwrap(items.last?.barcode)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = Item.match(barcode: targetBarcode, in: context)
        }

        XCTAssertLessThan(elapsed, .seconds(1), "a single predicate-backed barcode lookup should stay near-constant time regardless of catalog size")
    }

    func testExpirySortAndFilterStaysFastAt5000Items() throws {
        makeCatalog(count: 5_000)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let fetched = (try? context.fetch(FetchDescriptor<Item>())) ?? []
            // Same shape of work as StockListView's visibleItems: filter to expiring-soon, then
            // sort by earliest best-before — both of which read the `lots` relationship per item.
            let expiringSoon = fetched.filter { item in item.sortedLots.contains { $0.isExpiringSoon } }
            _ = expiringSoon.sorted { lhs, rhs in
                switch (lhs.earliestBestBefore, rhs.earliestBestBefore) {
                case let (lhsDate?, rhsDate?): return lhsDate < rhsDate
                case (nil, nil): return lhs.name < rhs.name
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        }

        XCTAssertLessThan(elapsed, .seconds(2), "filtering + sorting the full 5,000-item catalog by expiry should complete well under this ceiling")
    }

    func testStartSessionCompletesAt5000Items() async throws {
        let items = makeCatalog(count: 5_000)

        let clock = ContinuousClock()
        let start = clock.now
        _ = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: items, context: context)
        let elapsed = clock.now - start

        XCTAssertLessThan(elapsed, .seconds(5), "starting a stock-take session against the full catalog should complete in a few seconds, not hang")
    }
}
