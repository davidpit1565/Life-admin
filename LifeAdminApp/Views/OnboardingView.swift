import SwiftUI

/// Shown once, before the AI-consent screen and the permission prompts, so a first-time user
/// understands what the app does and why it's about to ask for access — instead of being hit
/// with unexplained system dialogs before they've done anything. Built for the audience this app
/// is actually for: people with too much on their mind already, who need this to be immediately
/// obvious, not another thing to figure out.
struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                OnboardingPageView(
                    systemImage: "brain.head.profile",
                    title: String(localized: "onboarding.page1.title"),
                    body: String(localized: "onboarding.page1.body")
                ).tag(0)
                OnboardingPageView(
                    systemImage: "text.bubble.fill",
                    title: String(localized: "onboarding.page2.title"),
                    body: String(localized: "onboarding.page2.body")
                ).tag(1)
                OnboardingPageView(
                    systemImage: "checkmark.shield.fill",
                    title: String(localized: "onboarding.page3.title"),
                    body: String(localized: "onboarding.page3.body")
                ).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(page == 2 ? String(localized: "onboarding.getStarted") : String(localized: "onboarding.next")) {
                if page == 2 {
                    onFinish()
                } else {
                    withAnimation { page += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

private struct OnboardingPageView: View {
    let systemImage: String
    let title: String
    let body: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}
