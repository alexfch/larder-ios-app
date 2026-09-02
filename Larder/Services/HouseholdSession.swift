import Foundation
import FirebaseAuth
import FirebaseFirestore

/// One household the signed-in identity already belongs to -- just enough to render a row on
/// `HouseholdSetupView`'s "or continue in a household you already belong to" list.
struct AccessibleHousehold: Identifiable, Equatable {
    let id: String
    let joinCode: String
}

enum HouseholdSessionError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Something went wrong — you're not signed in. Try restarting the app."
        }
    }
}

/// Resolves which household this device's already-signed-in identity belongs to, per ADR-0003's
/// multi-device design: a household has its own random document ID with a `memberUids` array, not
/// the auth UID itself, so a device either creates a new household or joins an existing one via a
/// short human-typed code. As of Phase 1, real sign-in (`AuthSession`) is a mandatory gate before
/// this class ever runs — it no longer signs in anonymously itself; every method here assumes
/// `Auth.auth().currentUser` is already a real, non-anonymous user.
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

    /// Households the signed-in identity already belongs to, for `HouseholdSetupView` to offer as
    /// a shortcut below Create/Join -- populated by `loadAccessibleHouseholds()`, which that view
    /// calls when it appears. Covers a device being set up for an account that already has access
    /// to one or more households from elsewhere, without forcing a fresh join-code round trip.
    private(set) var accessibleHouseholds: [AccessibleHousehold] = []

    private static let householdIdDefaultsKey = "com.bolzhelarskyi.larder.householdId"
    private let firestore = FirestoreDatabase.instance()

    var householdId: String? {
        if case .ready(let id) = state { return id }
        return nil
    }

    /// Resolves this device's household from a locally remembered ID (re-verified against the
    /// server) or surfaces the create/join screen. Assumes `AuthSession` has already established
    /// a real, signed-in identity before this runs.
    func start() async {
        state = .resolving
        do {
            let uid = try currentUid()
            if let savedId = UserDefaults.standard.string(forKey: Self.householdIdDefaultsKey) {
                if await isMember(uid: uid, householdId: savedId) {
                    state = .ready(householdId: savedId)
                    return
                }
                // The saved ID is no longer valid (e.g. reinstalled, or removed from the
                // household elsewhere) -- forget it and fall through to setup instead of leaving
                // the app stuck pointing at a household this device can't read.
                UserDefaults.standard.removeObject(forKey: Self.householdIdDefaultsKey)
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
            let uid = try currentUid()
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

            UserDefaults.standard.set(householdRef.documentID, forKey: Self.householdIdDefaultsKey)
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

    /// Forgets this device's remembered household id -- call when the signed-in identity changes
    /// (`LarderApp` does this on logout). `householdIdDefaultsKey` is a single, account-agnostic
    /// key: if it's left set after signing out, the *next* account to sign in on this device
    /// inherits the *previous* account's household id in `start()`, which then fails Security
    /// Rules' membership check (this uid was never added to that household). `isMember` already
    /// treats that failure as "not a member" rather than crashing -- but reaching that point at
    /// all was observed to be slow enough, on a cold Firestore connection right after sign-up, to
    /// look like a hang. Clearing the key on identity change removes the bad state at its source
    /// instead of only handling its symptom.
    static func forgetCachedHousehold() {
        UserDefaults.standard.removeObject(forKey: Self.householdIdDefaultsKey)
    }

    /// Fetches every household the signed-in identity is already a member of, for the "or
    /// continue in a household you already belong to" list on `HouseholdSetupView`. Best-effort:
    /// a failed query just leaves the list empty (or stale) rather than surfacing an error --
    /// Create/Join both remain available regardless, so this is a convenience, not a gate.
    func loadAccessibleHouseholds() async {
        guard let uid = try? currentUid() else { return }
        do {
            let snapshot = try await firestore.collection("households")
                .whereField("memberUids", arrayContains: uid)
                .getDocuments()
            accessibleHouseholds = snapshot.documents.compactMap { document in
                guard let joinCode = document.data()["joinCode"] as? String else { return nil }
                return AccessibleHousehold(id: document.documentID, joinCode: joinCode)
            }
        } catch {
            accessibleHouseholds = []
        }
    }

    /// Switches this device directly to a household from `accessibleHouseholds`, skipping the
    /// join-code round trip -- membership is already guaranteed by the query that produced it
    /// (and re-enforced server-side by Security Rules regardless), so no re-verification here.
    func selectHousehold(_ householdId: String) {
        UserDefaults.standard.set(householdId, forKey: Self.householdIdDefaultsKey)
        state = .ready(householdId: householdId)
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
            let uid = try currentUid()
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

            UserDefaults.standard.set(householdId, forKey: Self.householdIdDefaultsKey)
            state = .ready(householdId: householdId)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Returns whether `uid` is a member of `householdId` — `false` both when the household
    /// genuinely doesn't list this uid, and when the read itself is rejected (e.g. a saved id left
    /// over from a different account that was signed in on this device before, pointing at a
    /// household this uid was never added to). Both cases mean the same thing to `start()`: this
    /// saved id can't be trusted, so it should fall through to setup — not throw and surface a raw
    /// Firestore permission error for what is, from the user's perspective, an unremarkable "this
    /// account doesn't have a household yet" case.
    private func isMember(uid: String, householdId: String) async -> Bool {
        guard let snapshot = try? await firestore.collection("households").document(householdId).getDocument(),
              let memberUids = snapshot.data()?["memberUids"] as? [String] else {
            return false
        }
        return memberUids.contains(uid)
    }

    /// Reads the uid of the already-signed-in user established by `AuthSession` before this class
    /// ever runs. Throwing (rather than falling back to an anonymous sign-in, as this used to)
    /// means a genuine ordering bug fails loudly instead of silently minting a throwaway identity.
    private func currentUid() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw HouseholdSessionError.notSignedIn
        }
        return uid
    }

    /// Excludes visually ambiguous characters (0/O, 1/I/L) since this code is meant to be read off
    /// one screen and typed into another.
    private static func generateJoinCode(length: Int = 6) -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
