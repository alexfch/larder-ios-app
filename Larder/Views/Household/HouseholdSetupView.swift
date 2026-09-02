import SwiftUI

/// Shown when this device isn't yet resolved to a household (`HouseholdSession.state ==
/// .needsSetup`): either start a new household or join an existing one with the short code shown
/// on another device, per ADR-0003's join-code pairing design.
struct HouseholdSetupView: View {
    let session: HouseholdSession

    private enum Mode {
        case choose, join
    }

    @State private var mode: Mode = .choose
    @State private var joinCode: String = ""
    @State private var isWorking = false
    @State private var validationMessage: String?

    /// Combines a local, pre-submit validation message (e.g. an empty code) with whatever error
    /// `session.state` last reported -- read directly from `session.state` rather than mirrored
    /// into local `@State` via `onChange`, so a session that's already `.error` when this view
    /// first appears (e.g. after `.needsSetup`/`.error` are routed to the same view in
    /// `LarderApp`) shows its message immediately instead of only on the next transition.
    private var errorMessage: String? {
        if let validationMessage { return validationMessage }
        if case .error(let message) = session.state { return message }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                eyebrow: "LARDER",
                title: mode == .choose ? "Set Up Household" : "Join Household"
            )

            VStack(spacing: 20) {
                switch mode {
                case .choose:
                    Text("Create a new household, or join one that's already set up on another device.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.larderSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    PrimaryButton(title: "Create New Household", isEnabled: !isWorking) {
                        create()
                    }
                    .padding(.horizontal, 20)

                    SecondaryButton(title: "Join Existing Household", isEnabled: !isWorking) {
                        mode = .join
                    }
                    .padding(.horizontal, 20)

                    if !session.accessibleHouseholds.isEmpty {
                        accessibleHouseholdsList
                    }

                case .join:
                    Text("Enter the code shown on the device that's already set up.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.larderSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    TextField("6-character code", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .overlay(Rectangle().strokeBorder(Color.larderDivider, lineWidth: 1))
                        .padding(.horizontal, 40)

                    PrimaryButton(title: "Join", isEnabled: !isWorking && !joinCode.isEmpty) {
                        join()
                    }
                    .padding(.horizontal, 20)

                    SecondaryButton(title: "Back", isEnabled: !isWorking) {
                        mode = .choose
                        validationMessage = nil
                    }
                    .padding(.horizontal, 20)
                }

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
        .task {
            await session.loadAccessibleHouseholds()
        }
    }

    /// "Or continue in a household you already belong to" -- shown below Create/Join when this
    /// signed-in identity already has access to at least one household (e.g. a second device
    /// being set up for an existing account), so it doesn't have to go through the join-code flow
    /// just to reach a household it's already a member of.
    private var accessibleHouseholdsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Or continue in a household you already belong to")
                .font(.system(size: 13))
                .foregroundStyle(Color.larderSecondaryText)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(session.accessibleHouseholds) { household in
                    Button {
                        select(household)
                    } label: {
                        HStack {
                            Text("Household \(household.joinCode)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.larderInk)
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)

                    if household.id != session.accessibleHouseholds.last?.id {
                        Divider().overlay(Color.larderDivider)
                    }
                }
            }
            .background(Color.white)
            .overlay(Rectangle().strokeBorder(Color.larderDivider, lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func select(_ household: AccessibleHousehold) {
        validationMessage = nil
        isWorking = true
        session.selectHousehold(household.id)
    }

    private func create() {
        validationMessage = nil
        isWorking = true
        Task { await session.createHousehold() }
    }

    private func join() {
        validationMessage = nil
        isWorking = true
        Task { await session.joinHousehold(code: joinCode) }
    }
}
