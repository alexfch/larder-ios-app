import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Resolves this device's identity (Firebase Anonymous Auth) and which household it belongs to,
/// per ADR-0003's corrected multi-device design: a household has its own random document ID with
/// a `memberUids` array, not the auth UID itself. Plain Anonymous Auth mints a different,
/// unrelated UID on every device with no built-in way to share one identity across devices, so a
/// device either creates a new household or joins an existing one via a short human-typed code.
@MainActor
@Observable
final class HouseholdSession {
    enum State: Equatable {
        case resolving
        case needsSetup
        case ready(householdId: String)
        case error(String)
    }

    private(set) var state: State = .resolving

    /// Set only immediately after `createHousehold()` succeeds this launch, so the setup flow can
    /// show the new code once before handing off to the main app -- this is the only moment that
    /// code is otherwise surfaced anywhere, since there's no household/settings screen yet to
    /// revisit it later.
    private(set) var justCreatedJoinCode: String?

    private let householdIdDefaultsKey = "com.bolzhelarskyi.larder.householdId"
    private let firestore = FirestoreDatabase.instance()

    var householdId: String? {
        if case .ready(let id) = state { return id }
        return nil
    }

    /// Signs in anonymously if needed, then resolves this device's household from a locally
    /// remembered ID (re-verified against the server) or surfaces the create/join screen.
    func start() async {
        state = .resolving
        do {
            let uid = try await signInIfNeeded()
            if let savedId = UserDefaults.standard.string(forKey: householdIdDefaultsKey) {
                if try await isMember(uid: uid, householdId: savedId) {
                    state = .ready(householdId: savedId)
                    return
                }
                // The saved ID is no longer valid (e.g. reinstalled, or removed from the
                // household elsewhere) -- forget it and fall through to setup instead of leaving
                // the app stuck pointing at a household this device can't read.
                UserDefaults.standard.removeObject(forKey: householdIdDefaultsKey)
            }
            state = .needsSetup
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Creates a new household with this device as its sole member, plus a short join code other
    /// devices can type in later. The household document and its join-code lookup entry are
    /// written in one batch so a join can never observe one without the other.
    func createHousehold() async {
        do {
            let uid = try await signInIfNeeded()
            let code = Self.generateJoinCode()
            let householdRef = firestore.collection("households").document()
            let batch = firestore.batch()
            batch.setData([
                "memberUids": [uid],
                "joinCode": code,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: householdRef)
            batch.setData([
                "householdId": householdRef.documentID,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: firestore.collection("joinCodes").document(code))
            try await batch.commit()

            UserDefaults.standard.set(householdRef.documentID, forKey: householdIdDefaultsKey)
            justCreatedJoinCode = code
            state = .ready(householdId: householdRef.documentID)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Dismisses the one-time "household created" confirmation once the user has seen (and,
    /// presumably, noted down) the join code for pairing a second device later.
    func acknowledgeHouseholdCreated() {
        justCreatedJoinCode = nil
    }

    /// Joins an existing household by its short code. The `joinCodes` collection only ever maps a
    /// code to a household ID (see `firestore.rules`) -- it's readable by any signed-in device
    /// specifically so a device can resolve a code before it's a member of anything, without that
    /// read exposing the household's actual data. Membership itself is granted by a narrowly-scoped
    /// update that Security Rules only allow to append the caller's own uid to `memberUids`.
    func joinHousehold(code: String) async {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCode.isEmpty else {
            state = .error("Enter the code from the other device.")
            return
        }
        do {
            let uid = try await signInIfNeeded()
            let codeSnapshot = try await firestore.collection("joinCodes").document(normalizedCode).getDocument()
            guard let householdId = codeSnapshot.data()?["householdId"] as? String else {
                state = .error("That code doesn't match a household. Double-check it and try again.")
                return
            }
            try await firestore.collection("households").document(householdId).updateData([
                "memberUids": FieldValue.arrayUnion([uid])
            ])
            // Force a server round-trip for this household's data now (rather than relying on the
            // listeners the rest of the app attaches after setup) so the local cache is already
            // populated before this device is treated as ready -- see ADR-0003's first-login/
            // offline note: a brand-new device needs one successful connection before its
            // client-derived on-hand totals have anything to compute from.
            _ = try await firestore.collection("households").document(householdId)
                .collection("items").getDocuments(source: .server)
            _ = try await firestore.collection("households").document(householdId)
                .collection("transactions").getDocuments(source: .server)

            UserDefaults.standard.set(householdId, forKey: householdIdDefaultsKey)
            state = .ready(householdId: householdId)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func isMember(uid: String, householdId: String) async throws -> Bool {
        let snapshot = try await firestore.collection("households").document(householdId).getDocument()
        guard let memberUids = snapshot.data()?["memberUids"] as? [String] else { return false }
        return memberUids.contains(uid)
    }

    @discardableResult
    private func signInIfNeeded() async throws -> String {
        if let user = Auth.auth().currentUser {
            return user.uid
        }
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }

    /// Excludes visually ambiguous characters (0/O, 1/I/L) since this code is meant to be read off
    /// one screen and typed into another.
    private static func generateJoinCode(length: Int = 6) -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
