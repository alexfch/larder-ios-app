import SwiftUI

/// Shown when the device has no real, signed-in identity yet (`AuthSession.state ==
/// .needsSignIn`) — the mandatory first screen, before a household can be created or joined.
/// Email + password only for now; Google/Apple Sign-In are later phases (see `AuthSession`).
struct AuthView: View {
    let session: AuthSession

    private enum Mode {
        case signUp, logIn
    }

    @State private var mode: Mode = .signUp
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isWorking = false
    @State private var validationMessage: String?

    /// Combines a local, pre-submit validation message with whatever error `session.state` last
    /// reported -- read directly from `session.state` rather than mirrored into local `@State`,
    /// so an already-`.error` session shows its message immediately on first appearance. Mirrors
    /// the same pattern `HouseholdSetupView` uses.
    private var errorMessage: String? {
        if let validationMessage { return validationMessage }
        if case .error(let message) = session.state { return message }
        return nil
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: "LARDER",
                title: mode == .signUp ? "Create Account" : "Log In"
            )

            VStack(spacing: 20) {
                Text(mode == .signUp
                     ? "Create an account, then set up or join your household."
                     : "Log in to your account.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.larderSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding(12)
                        .background(Color.white)
                        .overlay(Rectangle().strokeBorder(Color.larderDivider, lineWidth: 1))

                    SecureField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.white)
                        .overlay(Rectangle().strokeBorder(Color.larderDivider, lineWidth: 1))
                }
                .padding(.horizontal, 40)

                PrimaryButton(title: mode == .signUp ? "Sign Up" : "Log In", isEnabled: !isWorking && canSubmit) {
                    submit()
                }
                .padding(.horizontal, 20)

                Button {
                    mode = mode == .signUp ? .logIn : .signUp
                    validationMessage = nil
                } label: {
                    Text(mode == .signUp ? "Already have an account? Log in" : "New here? Create an account")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.larderAccent)
                }
                .disabled(isWorking)

                if isWorking {
                    ProgressView()
                        .padding(.top, 4)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.larderAccent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.top, 12)

            Spacer()
        }
        .background(Color.larderBackground.ignoresSafeArea())
        .onChange(of: session.state) { _, _ in
            isWorking = false
        }
    }

    private func submit() {
        validationMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty else {
            validationMessage = "Enter your email."
            return
        }
        guard !password.isEmpty else {
            validationMessage = "Enter your password."
            return
        }
        isWorking = true
        Task {
            switch mode {
            case .signUp:
                await session.signUp(email: trimmedEmail, password: password)
            case .logIn:
                await session.signIn(email: trimmedEmail, password: password)
            }
        }
    }
}
