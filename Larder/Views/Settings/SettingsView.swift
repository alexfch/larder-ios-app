import SwiftUI
import FirebaseAuth

/// The fourth tab, after Stock. Currently just account info and Log Out -- a natural home for
/// household-management actions (rename, leave, invite) once those exist (see ADR-0004), but
/// nothing here depends on that yet.
struct SettingsView: View {
    @Environment(AuthSession.self) private var authSession
    @State private var isConfirmingLogOut = false

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
    }
}
