import SwiftUI
import FirebaseCore

@main
struct LarderApp: App {
    @State private var toastCenter: ToastCenter
    @State private var authSession: AuthSession
    @State private var householdSession: HouseholdSession

    /// Configures Firebase (Firestore + Auth) before any view or service touches those SDKs. No
    /// `AppDelegate`/`@UIApplicationDelegateAdaptor` — this app has never had one, and
    /// `FirebaseApp.configure()` is a plain synchronous call that has no need for UIKit
    /// app-lifecycle hooks, so adding one just for this would be unnecessary ceremony.
    ///
    /// `toastCenter`/`authSession`/`householdSession` are assigned explicitly here, in this order,
    /// rather than via `= ToastCenter()`/etc. default-value expressions on the property
    /// declarations: a struct's stored-property default values are evaluated to satisfy definite
    /// initialization *before* a custom `init`'s own body runs, not after. Both `AuthSession` and
    /// `HouseholdSession` touch Firebase Auth/Firestore in their own `init`, so a default-value
    /// expression for either would have run — and crashed with "call FirebaseApp.configure()
    /// first" — before this body's `FirebaseApp.configure()` call ever executed. Explicit
    /// assignment here guarantees the real order: configure, then construct anything that touches
    /// Firebase.
    init() {
        FirebaseApp.configure()
        _toastCenter = State(initialValue: ToastCenter())
        _authSession = State(initialValue: AuthSession())
        _householdSession = State(initialValue: HouseholdSession())
    }

    var body: some Scene {
        WindowGroup {
            // Two gates, in order: real sign-in (Phase 1 — email/password for now, Google/Apple
            // later), then household resolution (ADR-0003) — sign-up happens before a household
            // can be created or joined, not after, so there's no anonymous-session data to carry
            // across the transition the way an earlier design (linking an existing anonymous
            // session) would have needed.
            Group {
                switch authSession.state {
                case .resolving:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.larderBackground.ignoresSafeArea())
                case .needsSignIn, .error:
                    AuthView(session: authSession)
                case .signedIn:
                    switch householdSession.state {
                    case .resolving:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.larderBackground.ignoresSafeArea())
                    case .needsSetup, .error:
                        HouseholdSetupView(session: householdSession)
                    case .ready(let householdId):
                        if let code = householdSession.justCreatedJoinCode {
                            HouseholdCreatedConfirmationView(joinCode: code) {
                                householdSession.acknowledgeHouseholdCreated()
                            }
                        } else {
                            HouseholdReadyView(householdId: householdId)
                        }
                    }
                }
            }
            .environment(toastCenter)
            .overlay(ToastOverlay(message: toastCenter.message))
            // The design system (Color.larderBackground etc.) is light-only for now;
            // lock appearance so Form-based screens don't flip to a native dark look
            // that clashes with the rest of the app. Revisit if real Dark Mode support
            // gets built later.
            .preferredColorScheme(.light)
            .task {
                await authSession.start()
            }
            // `.task(id:)` re-runs when the given value changes and is otherwise a no-op — a
            // reliable way to say "run this once a value becomes available". (`catalogStore`
            // construction used to be a second `.task(id:)` here, keyed on
            // `householdSession.householdId` — removed after it proved unreliable when its
            // triggering state change (`householdSession.state` going `.ready`) landed in the
            // same async hop as this task's own `authSession.uid`-triggered chain: on a live
            // first-time create-household run, the household would be created and confirmed, but
            // the app would then hang on a bare spinner instead of reaching `RootTabView` — force-
            // quitting and relaunching always resolved cleanly, confirming the underlying data was
            // fine and this was purely a missed reactive trigger, not a real state bug. Since
            // `CatalogStore.init` is fully synchronous — it only starts fire-and-forget Firestore
            // listeners, nothing `await`s — it doesn't need a `Task` at all: `HouseholdReadyView`
            // below now constructs it directly in its own `init`, which SwiftUI guarantees runs
            // exactly once for a given household id, with no async race to lose.
            .task(id: authSession.uid) {
                guard authSession.uid != nil else { return }
                await householdSession.start()
            }
        }
    }
}

/// Hosts the main app for one resolved household. Takes `householdId` as a plain `init`
/// parameter (not observed reactively) and builds its `CatalogStore` directly in `init` — see the
/// comment on `LarderApp`'s old `.task(id:)` above for why this replaced a separate reactive task.
/// SwiftUI runs a view's `@State` initial-value expressions exactly once, the first time it
/// creates that view's identity, and reuses them across every subsequent re-render at the same
/// position in the tree — exactly the "construct once per household, not once per render" lifetime
/// `CatalogStore`'s Firestore listeners need.
private struct HouseholdReadyView: View {
    @State private var catalogStore: CatalogStore

    init(householdId: String) {
        _catalogStore = State(initialValue: CatalogStore(householdId: householdId))
    }

    var body: some View {
        RootTabView()
            .environment(catalogStore)
    }
}
