import SwiftUI
import FirebaseAuth

/// The fourth tab, after Stock. Account info, the household roster with Roles enforcement
/// (ADR-0004), and Log Out -- a natural home for further household-management actions (rename,
/// invite) once those exist, but nothing here depends on them yet.
struct SettingsView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(HouseholdSession.self) private var householdSession
    @Environment(CatalogStore.self) private var store
    @Environment(ToastCenter.self) private var toastCenter
    @State private var isConfirmingLogOut = false
    @State private var isConfirmingLeave = false
    /// The roster row a tap opened an action sheet for -- only ever set when the viewer is an
    /// Admin and the row isn't their own (see `sortedRoster`'s `ForEach`).
    @State private var selectedMember: RosterMember?

    private var currentUid: String? { Auth.auth().currentUser?.uid }

    private var myEntry: RosterMember? {
        guard let currentUid else { return nil }
        return store.roster.first { $0.linkedUids.contains(currentUid) }
    }

    private var isAdmin: Bool { myEntry?.role == .admin }

    private var adminCount: Int {
        store.roster.filter { $0.role == .admin }.count
    }

    /// Admins first, then by join order -- roughly "who's been here longest" within each tier,
    /// which reads more naturally than raw creation-timestamp order mixing the two.
    private var sortedRoster: [RosterMember] {
        store.roster.sorted { lhs, rhs in
            if (lhs.role == .admin) != (rhs.role == .admin) {
                return lhs.role == .admin
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: "LARDER", title: "Settings")

            VStack(spacing: 20) {
                if let email = Auth.auth().currentUser?.email {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SIGNED IN AS")
                            .trackedUppercase()
                            .font(LarderFont.eyebrow())
                            .foregroundStyle(Color.larderSecondaryText)
                        Text(email)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.larderInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                }

                if !sortedRoster.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("HOUSEHOLD")
                            .trackedUppercase()
                            .font(LarderFont.eyebrow())
                            .foregroundStyle(Color.larderSecondaryText)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(sortedRoster) { member in
                                // An Admin can tap any row but their own to promote/demote or
                                // remove that person -- self stays untappable both because the
                                // rules wouldn't allow self-role-changes/self-removal-as-remove
                                // anyway, and because "leave" (below) is the correct action for
                                // your own row, not "remove".
                                let isTappable = isAdmin && member.id != myEntry?.id
                                Group {
                                    if isTappable {
                                        Button {
                                            selectedMember = member
                                        } label: {
                                            rosterRow(member, showsChevron: true)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        rosterRow(member, showsChevron: false)
                                    }
                                }

                                if member.id != sortedRoster.last?.id {
                                    Divider().overlay(Color.larderDivider)
                                }
                            }
                        }
                        .background(Color.white)
                        .overlay(Rectangle().strokeBorder(Color.larderDivider, lineWidth: 1))
                    }
                    .padding(.horizontal, 20)

                    if myEntry != nil {
                        SecondaryButton(title: "Leave Household") {
                            leaveHousehold()
                        }
                        .padding(.horizontal, 20)
                    }
                }

                SecondaryButton(title: "Log Out") {
                    isConfirmingLogOut = true
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 12)

            Spacer()
        }
        .background(Color.larderBackground.ignoresSafeArea())
        .confirmationDialog(
            "Log out of Larder?",
            isPresented: $isConfirmingLogOut,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                authSession.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Leave this household?",
            isPresented: $isConfirmingLeave,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task { await householdSession.leaveHousehold() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            selectedMember.map(displayName(for:)) ?? "",
            isPresented: Binding(get: { selectedMember != nil }, set: { if !$0 { selectedMember = nil } }),
            titleVisibility: .visible
        ) {
            if let selectedMember, let role = selectedMember.role {
                Button(role == .admin ? "Demote to Member" : "Promote to Admin") {
                    toggleRole(for: selectedMember)
                }
            }
            if let selectedMember {
                Button("Remove from Household", role: .destructive) {
                    store.removeMember(uid: selectedMember.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func rosterRow(_ member: RosterMember, showsChevron: Bool) -> some View {
        HStack {
            Text(displayName(for: member))
                .font(.system(size: 15))
                .foregroundStyle(Color.larderInk)
            Spacer()
            if let role = member.role {
                Text(role == .admin ? "Admin" : "Member")
                    .trackedUppercase()
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.larderSecondaryText)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.larderSecondaryText)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    /// `displayName` is left blank at bootstrap (ADR-0004) with no edit UI yet to fill it in, so
    /// this falls back to something legible in the meantime: "You" for the signed-in caller's own
    /// entry, a role-based placeholder for anyone else's.
    private func displayName(for member: RosterMember) -> String {
        if !member.displayName.isEmpty { return member.displayName }
        if let currentUid, member.linkedUids.contains(currentUid) { return "You" }
        return member.role == .admin ? "Household admin" : "Household member"
    }

    private func toggleRole(for member: RosterMember) {
        guard let role = member.role else { return }
        var updated = member
        updated.role = role == .admin ? .member : .admin
        try? store.updateRosterMember(updated)
    }

    /// Blocks leaving client-side when the caller is the household's sole Admin, per
    /// `HouseholdSession.leaveHousehold()`'s doc comment on why that invariant lives here rather
    /// than in Security Rules.
    private func leaveHousehold() {
        guard !(isAdmin && adminCount <= 1) else {
            toastCenter.show("You're the only Admin — promote someone else first.")
            return
        }
        isConfirmingLeave = true
    }
}
