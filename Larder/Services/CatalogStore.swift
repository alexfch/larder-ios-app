import Foundation
import FirebaseAuth
import FirebaseFirestore

/// The read/write surface `StockService`, `CountSessionService`, and `BackupService` need,
/// factored out of `CatalogStore` so those services can be exercised in unit tests against an
/// in-memory fake (see `LarderTests`) instead of requiring a live Firestore connection or the
/// Firestore Local Emulator Suite, neither of which is available to a plain XCTest run.
@MainActor
protocol CatalogWriting: AnyObject {
    var items: [Item] { get }
    var transactions: [Transaction] { get }

    func item(id: String) -> Item?
    func item(matchingBarcode barcode: String) -> Item?
    func addItem(_ item: Item) throws

    func transactions(for itemId: String) -> [Transaction]
    func addTransaction(_ transaction: Transaction) throws
    func updateTransaction(_ transaction: Transaction) throws
    func deleteTransaction(id: String)

    func addCountSession(_ session: CountSession) throws
    func updateCountSession(_ session: CountSession) throws
    func lines(for sessionId: String) -> [CountLine]
    func addCountLine(_ line: CountLine, sessionId: String) throws
    func updateCountLine(_ line: CountLine, sessionId: String) throws
}

/// Firestore-backed replacement for SwiftData's `@Query`/`ModelContext`: attaches snapshot
/// listeners scoped to one household (ADR-0003) and exposes their current contents as
/// `@Observable` arrays, so SwiftUI views re-render the same way they did against `@Query` — just
/// driven by Firestore's local cache/listener pipeline instead of SwiftData's.
///
/// Write methods here are deliberately synchronous, not `async throws` awaiting server
/// acknowledgement: Firestore applies a write to its local cache (and fires listeners) immediately
/// on the calling thread, then syncs to the server in the background whenever connectivity allows.
/// Awaiting a write's completion would block until the *server* acknowledges it, which for an
/// offline-first app would hang UI actions like a check-in confirmation for as long as the device
/// stayed offline — exactly the failure this design exists to avoid (see ADR-0003).
@MainActor
@Observable
final class CatalogStore: CatalogWriting {
    let householdId: String

    private(set) var items: [Item] = []
    private(set) var transactions: [Transaction] = []
    private(set) var countSessions: [CountSession] = []
    /// This household's short pairing code (see `HouseholdSession`/ADR-0003), for screens that
    /// want to display it (e.g. as a reminder of which household you're in, or to read off to
    /// pair a second device) without needing to hold onto it separately.
    private(set) var joinCode: String?
    private var countLinesBySession: [String: [CountLine]] = [:]

    // Plain `Firestore.firestore()` -- the `(default)` database. See `HouseholdSession`'s copy of
    // this comment for why (Cloud Storage Security Rules can only ever read `(default)`).
    private let firestore = Firestore.firestore()
    // `nonisolated(unsafe)`: `deinit` is never actor-isolated even on a `@MainActor` class (Swift
    // can't guarantee which context deallocation happens on), so cleaning these up there needs to
    // read them outside MainActor isolation. Safe here because both arrays are otherwise only
    // touched from `init` (before any other access can race) and the listener-attaching methods,
    // which are themselves MainActor-isolated by the class.
    private nonisolated(unsafe) var listeners: [ListenerRegistration] = []
    private nonisolated(unsafe) var lineListeners: [String: ListenerRegistration] = [:]

    private var householdRef: DocumentReference {
        firestore.collection("households").document(householdId)
    }

    init(householdId: String) {
        self.householdId = householdId

        listeners.append(householdRef.collection("items").addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                assertionFailure("items listener failed: \(error)")
                return
            }
            self.items = snapshot?.documents.compactMap { try? $0.data(as: Item.self) } ?? []
        })

        listeners.append(householdRef.collection("transactions").addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                assertionFailure("transactions listener failed: \(error)")
                return
            }
            self.transactions = snapshot?.documents.compactMap { try? $0.data(as: Transaction.self) } ?? []
        })

        listeners.append(householdRef.collection("countSessions").addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                assertionFailure("countSessions listener failed: \(error)")
                return
            }
            self.countSessions = snapshot?.documents.compactMap { try? $0.data(as: CountSession.self) } ?? []
        })

        listeners.append(householdRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                assertionFailure("household listener failed: \(error)")
                return
            }
            self.joinCode = snapshot?.data()?["joinCode"] as? String
        })
    }

    deinit {
        listeners.forEach { $0.remove() }
        lineListeners.values.forEach { $0.remove() }
    }

    // MARK: Items

    func item(id: String) -> Item? {
        items.first { $0.id == id }
    }

    /// Single source of truth for barcode → catalog-item lookup (mirrors the old
    /// `Item.match(barcode:in:)`). Since the whole (5,000-item-capped) catalog is already synced
    /// locally, this is a linear scan over `items` rather than a server round trip.
    func item(matchingBarcode barcode: String) -> Item? {
        items.first { $0.barcode == barcode }
    }

    func addItem(_ item: Item) throws {
        try householdRef.collection("items").document(item.id).setData(from: item)
    }

    // MARK: Transactions

    func transactions(for itemId: String) -> [Transaction] {
        transactions.filter { $0.itemId == itemId }
    }

    /// Stamps `performedByUid` with the currently signed-in uid before writing -- the one place
    /// that happens, so `StockService`/`BackupService` can build `Transaction` values without
    /// knowing anything about Firebase Auth (see `Transaction.performedByUid`'s doc comment).
    /// Doesn't overwrite an already-set value, so a caller that has a real reason to set it
    /// explicitly (none does today) isn't silently clobbered.
    func addTransaction(_ transaction: Transaction) throws {
        var stamped = transaction
        if stamped.performedByUid == nil {
            stamped.performedByUid = Auth.auth().currentUser?.uid
        }
        try householdRef.collection("transactions").document(stamped.id).setData(from: stamped)
    }

    func updateTransaction(_ transaction: Transaction) throws {
        try householdRef.collection("transactions").document(transaction.id).setData(from: transaction)
    }

    func deleteTransaction(id: String) {
        householdRef.collection("transactions").document(id).delete()
    }

    // MARK: Count sessions

    func addCountSession(_ session: CountSession) throws {
        try householdRef.collection("countSessions").document(session.id).setData(from: session)
    }

    func updateCountSession(_ session: CountSession) throws {
        try householdRef.collection("countSessions").document(session.id).setData(from: session)
    }

    /// Lazily attaches a listener for one session's lines the first time they're needed, rather
    /// than eagerly listening to every session's lines (including old applied/discarded ones) up
    /// front.
    func observeLines(for sessionId: String) {
        guard lineListeners[sessionId] == nil else { return }
        lineListeners[sessionId] = householdRef.collection("countSessions").document(sessionId).collection("lines")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    assertionFailure("countSession lines listener failed: \(error)")
                    return
                }
                self.countLinesBySession[sessionId] = snapshot?.documents.compactMap { try? $0.data(as: CountLine.self) } ?? []
            }
    }

    func lines(for sessionId: String) -> [CountLine] {
        countLinesBySession[sessionId] ?? []
    }

    func addCountLine(_ line: CountLine, sessionId: String) throws {
        try householdRef.collection("countSessions").document(sessionId).collection("lines").document(line.id).setData(from: line)
    }

    func updateCountLine(_ line: CountLine, sessionId: String) throws {
        try householdRef.collection("countSessions").document(sessionId).collection("lines").document(line.id).setData(from: line)
    }
}
