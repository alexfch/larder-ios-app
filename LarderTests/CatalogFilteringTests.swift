import XCTest
import SwiftData
@testable import Larder

/// Unit tests for the filter/sort rules extracted from `StockResultsView`, `CheckOutHubView`,
/// and `ManualPickResultsView` per the architecture review's "extract testable filter/sort
/// helpers" finding — these previously lived only as private computed properties inline in a
/// view body, unreachable without instantiating SwiftUI.
final class CatalogFilteringTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Item.self, Lot.self, Transaction.self, CountSession.self, CountLine.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    private func makeItem(name: String, qty: Double? = nil, exp: Date = .now) -> Item {
        let item = Item(name: name, kind: .unit, noun: "tin")
        context.insert(item)
        if let qty {
            StockService.checkIn(item: item, qty: qty, exp: exp, context: context)
        }
        return item
    }

    // MARK: stockVisibleItems

    func testStockVisibleItemsSortsBySoonestExpiryWithNoBatchItemsLast() {
        let soon = makeItem(name: "Soon", qty: 1, exp: Date(timeIntervalSinceNow: 86_400))
        let later = makeItem(name: "Later", qty: 1, exp: Date(timeIntervalSinceNow: 86_400 * 10))
        let noBatches = makeItem(name: "AAA No Batches")

        let result = CatalogFiltering.stockVisibleItems([later, noBatches, soon], expiringOnly: false)

        XCTAssertEqual(result.map(\.name), ["Soon", "Later", "AAA No Batches"], "no-batch items sort last regardless of name")
    }

    func testStockVisibleItemsRestrictsToExpiringSoonWhenRequested() {
        let expiringSoon = makeItem(name: "Expiring", qty: 1, exp: Date(timeIntervalSinceNow: 86_400))
        let expiringLater = makeItem(name: "Not Soon", qty: 1, exp: Date(timeIntervalSinceNow: 86_400 * 30))

        let result = CatalogFiltering.stockVisibleItems([expiringSoon, expiringLater], expiringOnly: true)

        XCTAssertEqual(result.map(\.name), ["Expiring"])
    }

    // MARK: checkOutShortlist

    func testCheckOutShortlistExcludesItemsWithNoStockOrNoBatches() {
        let inStock = makeItem(name: "In Stock", qty: 3, exp: .now)
        let noBatches = makeItem(name: "No Batches")

        let result = CatalogFiltering.checkOutShortlist([inStock, noBatches])

        XCTAssertEqual(result.map(\.name), ["In Stock"])
    }

    func testCheckOutShortlistRespectsLimit() {
        let items = (0..<8).map { makeItem(name: "Item \($0)", qty: 1, exp: Date(timeIntervalSinceNow: Double($0) * 86_400)) }

        let result = CatalogFiltering.checkOutShortlist(items, limit: 5)

        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result.map(\.name), ["Item 0", "Item 1", "Item 2", "Item 3", "Item 4"], "nearest-expiry first")
    }

    // MARK: manualPickFilteredItems

    func testManualPickFilteredItemsRestrictsToInStockOnlyInCheckOutMode() {
        let inStock = makeItem(name: "In Stock", qty: 2, exp: .now)
        let outOfStock = makeItem(name: "Out of Stock")

        let checkOutResult = CatalogFiltering.manualPickFilteredItems([inStock, outOfStock], mode: .checkOut)
        let checkInResult = CatalogFiltering.manualPickFilteredItems([inStock, outOfStock], mode: .checkIn)

        XCTAssertEqual(checkOutResult.map(\.name), ["In Stock"])
        XCTAssertEqual(checkInResult.map(\.name).sorted(), ["In Stock", "Out of Stock"], "check-in mode has no stock restriction")
    }
}
