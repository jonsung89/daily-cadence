import SwiftUI

/// Closing page. Final tap commits `hasCompletedOnboarding = true`
/// and the RootView gate flips, transitioning to the app shell.
struct OnboardingDonePage: View {
    let firstName: String?
    let pageIndex: Int
    let pageCount: Int
    let onFinish: () -> Void

    private var greeting: String {
        if let first = firstName, !first.isEmpty {
            return "You're set, \(first)"
        }
        return "You're set"
    }

    var body: some View {
        OnboardingChrome(
            pageIndex: pageIndex,
            pageCount: pageCount,
            canSkip: false,
            title: greeting,
            body: "Welcome to DailyCadence.",
            primaryLabel: "Start logging",
            onPrimary: {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onFinish()
            }
        ) {
            DoneIllustration()
                .padding(.top, Spacing.s4)
        } control: {
            EmptyView()
        }
    }
}
