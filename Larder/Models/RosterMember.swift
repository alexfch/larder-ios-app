import Foundation

enum AgeBand: String, Codable, CaseIterable {
    case infant, child, teen, adult
}

enum HouseholdRole: String, Codable {
    case admin, member
}

/// Firestore document shape for `/households/{householdId}/roster/{memberId}` (ADR-0004): the
/// household's roster of *people*, deliberately distinct from the household document's
/// `memberUids` (access control only, unchanged since ADR-0003) -- see the ADR for why conflating
/// "who can authenticate" with "who is a person in this household" was rejected.
///
/// `memberId` (this struct's `id`) is the creating/joining uid for a self-registered member --
/// `HouseholdSession.createHousehold()`/`joinHousehold(code:)` key each bootstrap entry by the
/// caller's own uid, which is also what lets `firestore.rules`' `isAdmin()` look up "my own
/// roster entry" with a direct `get()`, mirroring `isMember()`, rather than needing a query
/// Security Rules can't express. A no-login family member an Admin adds by hand instead gets a
/// generated id, since there's no uid to key it by.
struct RosterMember: Identifiable, Codable, Hashable {
    var id: String
    var displayName: String
    /// Empty for a no-login family member. Holds the creating/joining uid for a self-registered
    /// member today; may eventually hold more than one uid once account linking or a future
    /// "merge roster entries" feature exists -- multi-device dedup is explicitly deferred by the
    /// ADR, so two devices joining as the same real person produce two separate entries for now.
    var linkedUids: [String]
    var ageBand: AgeBand
    /// nil whenever `linkedUids` is empty -- a no-login entry has no login to exercise a role.
    var role: HouseholdRole?
    var createdAt: Date

    init(
        id: String,
        displayName: String = "",
        linkedUids: [String] = [],
        ageBand: AgeBand = .adult,
        role: HouseholdRole? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.linkedUids = linkedUids
        self.ageBand = ageBand
        self.role = role
        self.createdAt = createdAt
    }
}
