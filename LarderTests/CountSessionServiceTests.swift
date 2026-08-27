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
        XCTAssertEqual(b.sortedTransactions.first?.action, .adjust, "most recent transaction, by occurredAt")
        XCTAssertEqual(session.status, .applied)
    }

    func testApplyIsAllOrNothingWhenOneLineBecomesInfeasible() throws {
        // Regression test for the validate-then-apply fix: a session snapshots book quantity at
        // start, but stock can change before apply (e.g. a check-out elsewhere in the app). If
        // that leaves one line's adjustment infeasible, no line should be applied — not just the
        // one that failed — and the session must stay .inProgress, not get stuck half-applied.
        let feasible = makeItem(name: "Beans", qty: 5)
        let infeasible = makeItem(name: "Rice", qty: 5)
        let session = CountSessionService.startSession(mode: .checklist, blindCount: false, items: [feasible, infeasible], context: context)

        session.lines.first { $0.item === feasible }?.countedQty = 8 // +3, always feasible
        session.lines.first { $0.item === infeasible }?.countedQty = 1 // -4 on paper

        // Simulate stock moving between session start and apply (e.g. a concurrent check-out):
        // "infeasible" now only has 2 on hand, so removing 4 to match the count can't happen.
        try StockService.checkOut(item: infeasible, qty: 3, context: context)
        XCTAssertEqual(infeasible.onHandTotal, 2)

        XCTAssertThrowsError(try CountSessionService.apply(session, context: context)) { error in
            XCTAssertTrue(error is CountSessionServiceError)
        }

        XCTAssertEqual(feasible.onHandTotal, 5, "the feasible line must not be applied if any other line in the session fails validation")
        XCTAssertEqual(feasible.transactions.count, 1, "only the original check-in — no adjustment transaction leaked through")
        XCTAssertEqual(infeasible.onHandTotal, 2, "unchanged by the failed apply")
        XCTAssertEqual(session.status, .inProgress, "a failed apply must not advance session status")
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
