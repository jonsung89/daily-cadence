import SwiftUI

/// First page of the onboarding flow. Personal greeting using the
/// first name pulled from Apple/Google sign-in metadata; if that's
/// missing, falls back to a generic but warm welcome.
struct OnboardingWelcomePage: View {
    let firstName: String?
    let pageIndex: Int
    let pageCount: Int
    let onContinue: () -> Void

    private var greeting: String {
        if let first = firstName, !first.isEmpty {
            return "Hi, \(first)"
        }
        return "Welcome"
    }

    var body: some View {
        OnboardingChrome(
            pageIndex: pageIndex,
            pageCount: pageCount,
            canSkip: false,
            title: greeting,
            body: "Let's set up your space. Most of this is editable later in Settings.",
            primaryLabel: "Get started",
            onPrimary: onContinue
        ) {
            WelcomeIllustration()
                .padding(.top, Spacing.s4)
        } control: {
            EmptyView()
        }
    }
}
