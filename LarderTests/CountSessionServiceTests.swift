import XCTest
@testable import Larder

@MainActor
final class CountSessionServiceTests: XCTestCase {
    var store: InMemoryCatalogStore!

    override func setUpWithError() throws {
        store = InMemoryCatalogStore()
    }

    private func makeItem(name: String, qty: Double, exp: Date = .now) throws -> Item {
        let item = Item(name: name, kind: .unit, noun: "tin")
        try store.addItem(item)
        try StockService.checkIn(itemId: item.id, qty: qty, exp: exp, store: store)
        return item
    }

    private func onHandTotal(_ item: Item) -> Double {
        CatalogDerivation.onHandTotal(itemId: item.id, transactions: store.transactions)
    }

    private func line(for item: Item, in lines: [CountLine]) -> CountLine? {
        lines.first { $0.itemId == item.id }
    }

    func testStartSessionSnapshotsBookQuantityForEveryItem() async throws {
        let beans = try makeItem(name: "Beans", qty: 5)
        let rice = try makeItem(name: "Rice", qty: 2)

        let session = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: [beans, rice], store: store)
        let lines = store.lines(for: session.id)

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(line(for: beans, in: lines)?.bookQtyAtStart, 5)
        XCTAssertEqual(line(for: rice, in: lines)?.bookQtyAtStart, 2)
        XCTAssertEqual(session.status, .inProgress)
    }

    func testApplyWritesSignedAdjustmentOnlyForDifferingLines() async throws {
        let beans = try makeItem(name: "Beans", qty: 5)
        let rice = try makeItem(name: "Rice", qty: 2)
        let session = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: [beans, rice], store: store)
        var lines = store.lines(for: session.id)

        if var beansLine = line(for: beans, in: lines) {
            beansLine.countedQty = 5
            try store.updateCountLine(beansLine, sessionId: session.id)
        }
        if var riceLine = line(for: rice, in: lines) {
            riceLine.countedQty = 6
            try store.updateCountLine(riceLine, sessionId: session.id)
        }
        lines = store.lines(for: session.id)

        try CountSessionService.apply(session, lines: lines, items: [beans, rice], store: store)

        XCTAssertEqual(onHandTotal(beans), 5, "matching line should not generate a transaction")
        XCTAssertEqual(store.transactions(for: beans.id).count, 1, "only the original check-in")
        XCTAssertEqual(onHandTotal(rice), 6)
        XCTAssertEqual(store.transactions(for: rice.id).count, 2, "check-in plus one adjustment")
        XCTAssertEqual(
            CatalogDerivation.sortedTransactions(itemId: rice.id, transactions: store.transactions).first?.action,
            .adjust,
            "most recent transaction, by occurredAt"
        )
        XCTAssertEqual(store.countSessions.first { $0.id == session.id }?.status, .applied)
    }

    func testApplyIsAllOrNothingWhenOneLineBecomesInfeasible() async throws {
        // Regression test: a session snapshots book quantity at start, but stock can change
        // before apply (e.g. a check-out elsewhere in the app). If that leaves one line's
        // adjustment infeasible, no line should be applied — not just the one that failed — and
        // the session must stay .inProgress, not get stuck half-applied.
        let feasible = try makeItem(name: "Beans", qty: 5)
        let infeasible = try makeItem(name: "Rice", qty: 5)
        let session = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: [feasible, infeasible], store: store)
        var lines = store.lines(for: session.id)

        if var feasibleLine = line(for: feasible, in: lines) {
            feasibleLine.countedQty = 8 // +3, always feasible
            try store.updateCountLine(feasibleLine, sessionId: session.id)
        }
        if var infeasibleLine = line(for: infeasible, in: lines) {
            infeasibleLine.countedQty = 1 // -4 on paper
            try store.updateCountLine(infeasibleLine, sessionId: session.id)
        }

        // Simulate stock moving between session start and apply (e.g. a concurrent check-out):
        // "infeasible" now only has 2 on hand, so removing 4 to match the count can't happen.
        try StockService.checkOut(itemId: infeasible.id, qty: 3, store: store)
        XCTAssertEqual(onHandTotal(infeasible), 2)

        lines = store.lines(for: session.id)

        XCTAssertThrowsError(try CountSessionService.apply(session, lines: lines, items: [feasible, infeasible], store: store)) { error in
            XCTAssertTrue(error is CountSessionServiceError)
        }

        XCTAssertEqual(onHandTotal(feasible), 5, "the feasible line must not be applied if any other line in the session fails validation")
        XCTAssertEqual(store.transactions(for: feasible.id).count, 1, "only the original check-in — no adjustment transaction leaked through")
        XCTAssertEqual(onHandTotal(infeasible), 2, "unchanged by the failed apply")
        XCTAssertEqual(store.countSessions.first { $0.id == session.id }?.status, .inProgress, "a failed apply must not advance session status")
    }

    func testDiscardLeavesBalancesUntouched() async throws {
        let beans = try makeItem(name: "Beans", qty: 5)
        let session = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: [beans], store: store)
        if var beansLine = store.lines(for: session.id).first {
            beansLine.countedQty = 1
            try store.updateCountLine(beansLine, sessionId: session.id)
        }

        try CountSessionService.discard(session, store: store)

        XCTAssertEqual(onHandTotal(beans), 5)
        XCTAssertEqual(store.countSessions.first { $0.id == session.id }?.status, .discarded)
    }
}
