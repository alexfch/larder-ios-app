import SwiftUI
import FirebaseCore

@main
struct LarderApp: App {
    @State private var toastCenter: ToastCenter
    @State private var householdSession: HouseholdSession
    /// Created exactly once, the first time the household resolves to `.ready` — not inline in
    /// `body`, which SwiftUI re-invokes on every state change; constructing a fresh `CatalogStore`
    /// on each of those would tear down and reattach its Firestore listeners constantly instead
    /// of once per app session.
    @State private var catalogStore: CatalogStore?

    /// Configures Firebase (Firestore + Auth, per ADR-0003) before any view or service touches
    /// those SDKs. No `AppDelegate`/`@UIApplicationDelegateAdaptor` — this app has never had one,
    /// and `FirebaseApp.configure()` is a plain synchronous call that has no need for UIKit
    /// app-lifecycle hooks, so adding one just for this would be unnecessary ceremony.
    ///
    /// `toastCenter`/`householdSession` are assigned explicitly here, in this order, rather than
    /// via `= ToastCenter()`/`= HouseholdSession()` default-value expressions on the property
    /// declarations: a struct's stored-property default values are evaluated to satisfy definite
    /// initialization *before* a custom `init`'s own body runs, not after. `HouseholdSession`'s
    /// own `init` constructs `Firestore.firestore()`, so a default-value expression for it would
    /// have run — and crashed with "call FirebaseApp.configure() first" — before this body's
    /// `FirebaseApp.configure()` call ever executed. Explicit assignment here guarantees the real
    /// order: configure, then construct anything that touches Firebase.
    init() {
        FirebaseApp.configure()
        _toastCenter = State(initialValue: ToastCenter())
        _householdSession = State(initialValue: HouseholdSession())
    }

    var body: some Scene {
        WindowGroup {
            // Gate the app on household resolution (ADR-0003, Phase 4): sign in anonymously, then
            // either restore this device's known household, walk it through create/join, or show
            // the one-time join-code confirmation right after creating one. Only once a household
            // is resolved does a `CatalogStore` exist at all — the catalog itself now lives
            // entirely in Firestore, scoped to that household, with SwiftData retired.
            Group {
                switch householdSession.state {
                case .resolving:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.larderBackground.ignoresSafeArea())
                case .needsSetup, .error:
                    HouseholdSetupView(session: householdSession)
                case .ready:
                    if let code = householdSession.justCreatedJoinCode {
                        HouseholdCreatedConfirmationView(joinCode: code) {
                            householdSession.acknowledgeHouseholdCreated()
                        }
                    } else if let catalogStore {
                        RootTabView()
                            .environment(catalogStore)
                    } else {
                        // Momentary: `.onChange` below hasn't constructed `catalogStore` yet.
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.larderBackground.ignoresSafeArea())
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
                await householdSession.start()
            }
            // `.task(id:)` re-runs when `householdSession.householdId` changes value (nil ->
            // some id, once, for the life of the session) and is otherwise a no-op -- a more
            // reliable way to say "construct this once a value becomes available" than
            // `.onChange(of:)`, which compares against the *previous* value and can miss a
            // transition that lands in the same update cycle as other state changes (as it did
            // here: `justCreatedJoinCode` and `state` both change out from under `createHousehold()`
            // in the same async hop).
            .task(id: householdSession.householdId) {
                guard let householdId = householdSession.householdId, catalogStore == nil else { return }
                catalogStore = CatalogStore(householdId: householdId)
            }
        }
    }
}
