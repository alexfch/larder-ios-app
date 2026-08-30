import SwiftUI

/// Shown once, right after `HouseholdSession.createHousehold()` succeeds, so the join code has
/// somewhere to be seen before it's needed for pairing a second device. There's no household/
/// settings screen to revisit this later yet -- see `HouseholdSession.justCreatedJoinCode`.
struct HouseholdCreatedConfirmationView: View {
    let joinCode: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: "LARDER", title: "Household Created")

            VStack(spacing: 20) {
                Text("To add another device later, open Larder there and enter this code:")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.larderSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text(joinCode)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(Color.larderInk)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .overlay(Rectangle().strokeBorder(Color.larderDivider, lineWidth: 1))
                    .padding(.horizontal, 40)

                Text("There's no place to look this up again yet, so make a note of it now.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.larderSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                PrimaryButton(title: "Continue") {
                    onContinue()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .padding(.top, 12)

            Spacer()
        }
        .background(Color.larderBackground.ignoresSafeArea())
    }
}
