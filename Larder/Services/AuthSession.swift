import Foundation
import FirebaseAuth

/// Resolves this device's real, sign-in identity — the first gate the app passes through, before
/// `HouseholdSession` ever runs (per the Phase 1 auth design: sign-up happens before a household
/// can be created or joined, not after, so there's no anonymous-session data to preserve across
/// the transition — see ADR-0004's roadmap review and the Phase 1 discussion that superseded its
/// original "link an existing anonymous session" plan).
///
/// Email + password only for now (Google/Apple Sign-In are later phases). Firebase's email/
/// password provider is keyed on a real, verified email address, not an arbitrary username — a
/// synthetic-username workaround was considered and rejected (weaker account recovery, weaker
/// abuse protection) per the architecture review's Security Specialist findings.
@MainActor
@Observable
final class AuthSession {
    enum State: Equatable {
        case resolving
        case needsSignIn
        case signedIn(uid: String)
        case error(String)
    }

    private(set) var state: State = .resolving

    var uid: String? {
        if case .signedIn(let uid) = state { return uid }
        return nil
    }

    /// A leftover Anonymous Auth session from before this app version (or from this session's own
    /// testing) is deliberately treated as "not signed in" -- Anonymous Auth is no longer used to
    /// bootstrap identity at all now that sign-up is a mandatory first screen; an anonymous user
    /// left over from before is simply abandoned, not linked or migrated (see the Phase 1 decision
    /// this file implements).
    func start() async {
        state = .resolving
        if let user = Auth.auth().currentUser, !user.isAnonymous {
            state = .signedIn(uid: user.uid)
        } else {
            state = .needsSignIn
        }
    }

    func signUp(email: String, password: String) async {
        state = .resolving
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            state = .signedIn(uid: result.user.uid)
        } catch {
            state = .error(Self.message(for: error))
        }
    }

    func signIn(email: String, password: String) async {
        state = .resolving
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            state = .signedIn(uid: result.user.uid)
        } catch {
            state = .error(Self.message(for: error))
        }
    }

    /// Signs out of Firebase Auth and returns to `.needsSignIn`, which `LarderApp` reacts to by
    /// tearing down `householdSession` and `catalogStore` -- everything downstream of identity is
    /// re-derived from scratch the next time someone signs in, rather than trying to reset each
    /// piece in place.
    func signOut() {
        do {
            try Auth.auth().signOut()
            state = .needsSignIn
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Maps Firebase's `AuthErrorCode` cases to plain, actionable copy instead of surfacing SDK
    /// error strings verbatim -- the default `localizedDescription` for e.g. `.weakPassword` is
    /// technically accurate but reads like an SDK error, not app copy.
    private static func message(for error: Error) -> String {
        guard let code = AuthErrorCode(rawValue: (error as NSError).code) else {
            return error.localizedDescription
        }
        switch code {
        case .invalidEmail:
            return "That doesn't look like a valid email address."
        case .emailAlreadyInUse:
            return "An account with that email already exists — try logging in instead."
        case .weakPassword:
            return "Choose a password with at least 6 characters."
        case .wrongPassword, .invalidCredential:
            return "Incorrect email or password."
        case .userNotFound:
            return "No account found with that email — check it, or sign up instead."
        case .networkError:
            return "Couldn't reach the server. Check your connection and try again."
        default:
            return error.localizedDescription
        }
    }
}
