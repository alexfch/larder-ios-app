import XCTest
@testable import Larder

/// Unit tests for the filter/sort rules extracted from `StockResultsView`, `CheckOutHubView`,
/// and `ManualPickResultsView` per the architecture review's "extract testable filter/sort
/// helpers" finding — these previously lived only as private computed properties inline in a
/// view body, unreachable without instantiating SwiftUI.
@MainActor
final class CatalogFilteringTests: XCTestCase {
    var store: InMemoryCatalogStore!

    override func setUpWithError() throws {
        store = InMemoryCatalogStore()
    }

    private func makeItem(name: String, qty: Double? = nil, exp: Date = .now) throws -> Item {
        let item = Item(name: name, packaging: .packaged, packageName: "tin")
        try store.addItem(item)
        if let qty {
            try StockService.checkIn(itemId: item.id, qty: qty, exp: exp, store: store)
        }
        return item
    }

    // MARK: stockVisibleItems

    func testStockVisibleItemsSortsBySoonestExpiryWithNoBatchItemsLast() throws {
        let soon = try makeItem(name: "Soon", qty: 1, exp: Date(timeIntervalSinceNow: 86_400))
        let later = try makeItem(name: "Later", qty: 1, exp: Date(timeIntervalSinceNow: 86_400 * 10))
        let noBatches = try makeItem(name: "AAA No Batches")

        let result = CatalogFiltering.stockVisibleItems([later, noBatches, soon], transactions: store.transactions, expiringOnly: false)

        XCTAssertEqual(result.map(\.name), ["Soon", "Later", "AAA No Batches"], "no-batch items sort last regardless of name")
    }

    func testStockVisibleItemsRestrictsToExpiringSoonWhenRequested() throws {
        let expiringSoon = try makeItem(name: "Expiring", qty: 1, exp: Date(timeIntervalSinceNow: 86_400))
        let expiringLater = try makeItem(name: "Not Soon", qty: 1, exp: Date(timeIntervalSinceNow: 86_400 * 30))

        let result = CatalogFiltering.stockVisibleItems([expiringSoon, expiringLater], transactions: store.transactions, expiringOnly: true)

        XCTAssertEqual(result.map(\.name), ["Expiring"])
    }

    // MARK: checkOutShortlist

    func testCheckOutShortlistExcludesItemsWithNoStockOrNoBatches() throws {
        let inStock = try makeItem(name: "In Stock", qty: 3, exp: .now)
        let noBatches = try makeItem(name: "No Batches")

        let result = CatalogFiltering.checkOutShortlist([inStock, noBatches], transactions: store.transactions)

        XCTAssertEqual(result.map(\.name), ["In Stock"])
    }

    func testCheckOutShortlistRespectsLimit() throws {
        let items = try (0..<8).map { try makeItem(name: "Item \($0)", qty: 1, exp: Date(timeIntervalSinceNow: Double($0) * 86_400)) }

        let result = CatalogFiltering.checkOutShortlist(items, transactions: store.transactions, limit: 5)

        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result.map(\.name), ["Item 0", "Item 1", "Item 2", "Item 3", "Item 4"], "nearest-expiry first")
    }

    // MARK: manualPickFilteredItems

    func testManualPickFilteredItemsRestrictsToInStockOnlyInCheckOutMode() throws {
        let inStock = try makeItem(name: "In Stock", qty: 2, exp: .now)
        let outOfStock = try makeItem(name: "Out of Stock")

        let checkOutResult = CatalogFiltering.manualPickFilteredItems([inStock, outOfStock], transactions: store.transactions, mode: .checkOut)
        let checkInResult = CatalogFiltering.manualPickFilteredItems([inStock, outOfStock], transactions: store.transactions, mode: .checkIn)

        XCTAssertEqual(checkOutResult.map(\.name), ["In Stock"])
        XCTAssertEqual(checkInResult.map(\.name).sorted(), ["In Stock", "Out of Stock"], "check-in mode has no stock restriction")
    }
}
