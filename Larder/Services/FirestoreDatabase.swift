import FirebaseFirestore

/// The Firestore console's "Create database" flow defaults to a database literally named
/// `(default)`, but this project's database was created with an explicit custom ID instead
/// (`db-larder`) — the SDK's bare `Firestore.firestore()` only ever resolves the `(default)`
/// database, so every call site needs to name this one explicitly via `Firestore.firestore(database:)`.
enum FirestoreDatabase {
    static let id = "db-larder"

    static func instance() -> Firestore {
        Firestore.firestore(database: id)
    }
}
