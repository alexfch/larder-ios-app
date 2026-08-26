import XCTest
import SwiftData
@testable import Larder

final class CountSessionServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Item.self, Lot.self, Transaction.self, CountSession.self, CountLine.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    private func makeItem(name: String, qty: Double, exp: Date = .now) -> Item {
        let item = Item(name: name, kind: .unit, noun: "tin")
        context.insert(item)
        StockService.checkIn(item: item, qty: qty, exp: exp, context: context)
        return item
    }

    func testStartSessionSnapshotsBookQuantityForEveryItem() {
        let a = makeItem(name: "Beans", qty: 5)
        let b = makeItem(name: "Rice", qty: 2)

        let session = CountSessionService.startSession(mode: .checklist, blindCount: false, items: [a, b], context: context)

        XCTAssertEqual(session.lines.count, 2)
        XCTAssertEqual(session.lines.first { $0.item === a }?.bookQtyAtStart, 5)
        XCTAssertEqual(session.lines.first { $0.item === b }?.bookQtyAtStart, 2)
        XCTAssertEqual(session.status, .inProgress)
    }

    func testApplyWritesSignedAdjustmentOnlyForDifferingLines() throws {
        let a = makeItem(name: "Beans", qty: 5)
        let b = makeItem(name: "Rice", qty: 2)
        let session = CountSessionService.startSession(mode: .checklist, blindCount: false, items: [a, b], context: context)

        session.lines.first { $0.item === a }?.countedQty = 5
        session.lines.first { $0.item === b }?.countedQty = 6

        try CountSessionService.apply(session, context: context)

        XCTAssertEqual(a.onHandTotal, 5, "matching line should not generate a transaction")
        XCTAssertEqual(a.transactions.count, 1, "only the original check-in")
        XCTAssertEqual(b.onHandTotal, 6)
        XCTAssertEqual(b.transactions.count, 2, "check-in plus one adjustment")
        XCTAssertEqual(b.transactions.last?.action, .adjust)
        XCTAssertEqual(session.status, .applied)
    }

    func testDiscardLeavesBalancesUntouched() {
        let a = makeItem(name: "Beans", qty: 5)
        let session = CountSessionService.startSession(mode: .checklist, blindCount: false, items: [a], context: context)
        session.lines.first?.countedQty = 1

        CountSessionService.discard(session)

        XCTAssertEqual(a.onHandTotal, 5)
        XCTAssertEqual(session.status, .discarded)
    }
}
