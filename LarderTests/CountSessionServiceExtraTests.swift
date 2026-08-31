import XCTest
@testable import Larder

/// Additional `CountSessionService` coverage beyond `CountSessionServiceTests`: session
/// auto-numbering and resume semantics (FR-7.1), the reason tag flowing from a count line onto
/// the adjustment movement it produces (FR-7.3), and the "nothing differs" apply path.
@MainActor
final class CountSessionServiceExtraTests: XCTestCase {
    private let sessionNumberKey = "larder.nextCountSessionNumber"
    var store: InMemoryCatalogStore!

    override func setUpWithError() throws {
        store = InMemoryCatalogStore()
        UserDefaults.standard.removeObject(forKey: sessionNumberKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: sessionNumberKey)
    }

    private func makeItem(name: String, qty: Double) throws -> Item {
        let item = Item(name: name, kind: .unit, noun: "tin")
        try store.addItem(item)
        try StockService.checkIn(itemId: item.id, qty: qty, exp: .now, store: store)
        return item
    }

    private func line(for item: Item, in session: CountSession) -> CountLine? {
        store.lines(for: session.id).first { $0.itemId == item.id }
    }

    func testFirstSessionIsNumberedFiveHundredAndOneThenEachSubsequentSessionIncrements() async throws {
        let item = try makeItem(name: "Beans", qty: 1)

        let first = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: [item], store: store)
        let second = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: [item], store: store)

        XCTAssertEqual(first.sessionNumber, 501)
        XCTAssertEqual(first.displayNumber, "INV-501")
        XCTAssertEqual(second.sessionNumber, 502)
    }

    func testSessionNumberContinuesFromThePersistedCounter() async throws {
        UserDefaults.standard.set(720, forKey: sessionNumberKey)
        let item = try makeItem(name: "Beans", qty: 1)

        let session = await CountSessionService.startSession(mode: .scanSweep, blindCount: true, items: [item], store: store)

        XCTAssertEqual(session.sessionNumber, 720)
        XCTAssertEqual(session.mode, .scanSweep)
        XCTAssertTrue(session.blindCount)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: sessionNumberKey), 721)
    }

    func testAppliedAdjustmentCarriesTheReasonTagChosenOnTheCountLine() async throws {
        let item = try makeItem(name: "Beans", qty: 10)
        let session = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: [item], store: store)

        var countLine = try XCTUnwrap(line(for: item, in: session))
        countLine.countedQty = 7
        countLine.reasonTag = AdjustReason.spoiled.rawValue
        try store.updateCountLine(countLine, sessionId: session.id)

        try CountSessionService.apply(session, lines: store.lines(for: session.id), items: [item], store: store)

        let adjustment = try XCTUnwrap(
            CatalogDerivation.sortedTransactions(itemId: item.id, transactions: store.transactions)
                .first { $0.action == .adjust }
        )
        XCTAssertEqual(adjustment.qty, -3, "counted 7 against a book of 10")
        XCTAssertEqual(adjustment.reasonTag, AdjustReason.spoiled.rawValue)
        XCTAssertEqual(CatalogDerivation.onHandTotal(itemId: item.id, transactions: store.transactions), 7)
    }

    func testApplyingASessionWithNoDifferencesClosesItWithoutWritingAnyMovement() async throws {
        let item = try makeItem(name: "Beans", qty: 5)
        let session = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: [item], store: store)

        var countLine = try XCTUnwrap(line(for: item, in: session))
        countLine.countedQty = 5 // matches book exactly
        try store.updateCountLine(countLine, sessionId: session.id)

        try CountSessionService.apply(session, lines: store.lines(for: session.id), items: [item], store: store)

        XCTAssertEqual(store.transactions(for: item.id).count, 1, "only the original check-in — no adjustment")
        XCTAssertEqual(store.countSessions.first { $0.id == session.id }?.status, .applied)
    }

    func testStartSessionAgainstAnEmptyCatalogCreatesASessionWithNoLines() async throws {
        let session = await CountSessionService.startSession(mode: .checklist, blindCount: false, items: [], store: store)

        XCTAssertEqual(session.status, .inProgress)
        XCTAssertTrue(store.lines(for: session.id).isEmpty)
    }
}
