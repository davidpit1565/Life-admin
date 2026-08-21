import SwiftUI

/// Blocks the app on first launch until the user explicitly decides whether their typed text may
/// be sent to Gemini. Required, not optional politeness: Apple's App Review Guideline 5.1.2(i)
/// (updated Nov 2025) requires explicit, disclosed consent before sharing user data with
/// third-party AI, and a declined decision must leave the app fully usable — see
/// ItemStore.autonomyMode, which falls back to local-only parsing whenever consent isn't granted.
struct AIConsentView: View {
    var onDecision: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)

                Text(String(localized: "aiConsent.title"))
                    .font(.title2.bold())

                Text(String(localized: "aiConsent.body"))
                    .foregroundStyle(.secondary)

                Text(String(localized: "aiConsent.detail"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(String(localized: "aiConsent.agree")) {
                    onDecision("granted")
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button(String(localized: "aiConsent.decline")) {
                    onDecision("declined")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .navigationTitle(String(localized: "aiConsent.navTitle"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
