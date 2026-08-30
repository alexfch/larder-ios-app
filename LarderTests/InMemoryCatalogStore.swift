import Foundation
@testable import Larder

/// In-memory `CatalogWriting` fake used across the test suite in place of a real `CatalogStore`
/// (which requires a live Firestore connection or the Firestore Local Emulator Suite, neither
/// available to a plain XCTest run). Exercises exactly the same `StockService`/
/// `CountSessionService`/`BackupService` code paths the app uses — only the persistence
/// destination differs.
@MainActor
final class InMemoryCatalogStore: CatalogWriting {
    private(set) var items: [Item] = []
    private(set) var transactions: [Transaction] = []
    private(set) var countSessions: [CountSession] = []
    private var linesBySession: [String: [CountLine]] = [:]

    func item(id: String) -> Item? {
        items.first { $0.id == id }
    }

    func item(matchingBarcode barcode: String) -> Item? {
        items.first { $0.barcode == barcode }
    }

    func addItem(_ item: Item) throws {
        items.append(item)
    }

    func transactions(for itemId: String) -> [Transaction] {
        transactions.filter { $0.itemId == itemId }
    }

    func addTransaction(_ transaction: Transaction) throws {
        transactions.append(transaction)
    }

    func updateTransaction(_ transaction: Transaction) throws {
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        transactions[index] = transaction
    }

    func deleteTransaction(id: String) {
        transactions.removeAll { $0.id == id }
    }

    func addCountSession(_ session: CountSession) throws {
        countSessions.append(session)
    }

    func updateCountSession(_ session: CountSession) throws {
        guard let index = countSessions.firstIndex(where: { $0.id == session.id }) else { return }
        countSessions[index] = session
    }

    func lines(for sessionId: String) -> [CountLine] {
        linesBySession[sessionId] ?? []
    }

    func addCountLine(_ line: CountLine, sessionId: String) throws {
        linesBySession[sessionId, default: []].append(line)
    }

    func updateCountLine(_ line: CountLine, sessionId: String) throws {
        guard let index = linesBySession[sessionId]?.firstIndex(where: { $0.id == line.id }) else { return }
        linesBySession[sessionId]?[index] = line
    }
}
