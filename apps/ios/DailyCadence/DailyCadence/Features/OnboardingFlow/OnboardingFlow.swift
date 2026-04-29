import SwiftUI

/// Top-level container for the post-sign-in onboarding flow.
///
/// Holds the page-index state machine, in-progress profile edits, and
/// orchestrates the slide animation between pages. Each page is a
/// thin SwiftUI struct that calls back into this container's
/// `advance` / `skip` / `finish` methods — this keeps page views free
/// of cross-page state and makes the flow easy to reorder.
///
/// **Trigger gate:** `RootView` shows this whenever
/// `AppPreferencesStore.hasCompletedOnboarding == false` and the user
/// is signed in. Pressing through to the Done page sets the flag;
/// quitting mid-flow leaves it false so users resume from the start
/// next launch (intentional — partial-state recovery isn't worth the
/// complexity for a 6-page flow).
struct OnboardingFlow: View {
    @State private var page: Int = 0
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var profileSaving: Bool = false
    @State private var profileError: String?

    private let pageCount = 6

    var body: some View {
        ZStack {
            // Per-page slide transitions are local to this ZStack so
            // the chrome's tinted background (which depends on the
            // global ThemeStore) updates seamlessly across pages.
            Group {
                switch page {
                case 0:
                    OnboardingWelcomePage(
                        firstName: AuthStore.shared.firstName,
                        pageIndex: 0,
                        pageCount: pageCount,
                        onContinue: advance
                    )
                case 1:
                    OnboardingProfilePage(
                        firstName: $firstName,
                        lastName: $lastName,
                        pageIndex: 1,
                        pageCount: pageCount,
                        isSaving: profileSaving,
                        saveError: profileError,
                        onContinue: { Task { await saveProfileThenAdvance() } }
                    )
                case 2:
                    OnboardingThemeIconPage(
                        pageIndex: 2,
                        pageCount: pageCount,
                        onContinue: advance,
                        onSkip: advance
                    )
                case 3:
                    OnboardingNoteTypesPage(
                        pageIndex: 3,
                        pageCount: pageCount,
                        onContinue: advance,
                        onSkip: advance
                    )
                case 4:
                    OnboardingRemindersPage(
                        pageIndex: 4,
                        pageCount: pageCount,
                        onDone: advance
                    )
                default:
                    OnboardingDonePage(
                        firstName: AuthStore.shared.firstName,
                        pageIndex: 5,
                        pageCount: pageCount,
                        onFinish: finish
                    )
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .id(page)
        }
        .onAppear { hydrateFromAuthStore() }
    }

    /// Pre-fills profile fields from `AuthStore.firstName / lastName`
    /// (sourced from Apple/Google metadata). User can edit before
    /// pressing Continue, or skip to keep the OAuth-provided values.
    private func hydrateFromAuthStore() {
        if firstName.isEmpty { firstName = AuthStore.shared.firstName ?? "" }
        if lastName.isEmpty { lastName = AuthStore.shared.lastName ?? "" }
    }

    private func advance() {
        guard page < pageCount - 1 else { return }
        withAnimation(.easeInOut(duration: 0.32)) {
            page += 1
        }
    }

    private func finish() {
        AppPreferencesStore.shared.hasCompletedOnboarding = true
        // RootView observes the flag and swaps to the app shell. We
        // don't dismiss explicitly — the gate handles the transition.
    }

    /// Saves the profile to `auth.users.raw_user_meta_data` and
    /// advances on success. On failure, shows the error inline + lets
    /// the user retry or skip.
    @MainActor
    private func saveProfileThenAdvance() async {
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        // No-op fast path: if nothing changed vs. the OAuth-provided
        // values, skip the round-trip and just advance.
        if trimmedFirst == (AuthStore.shared.firstName ?? "")
            && trimmedLast == (AuthStore.shared.lastName ?? "") {
            advance()
            return
        }
        profileSaving = true
        defer { profileSaving = false }
        do {
            try await AuthStore.shared.updateProfile(
                firstName: trimmedFirst,
                lastName: trimmedLast
            )
            profileError = nil
            advance()
        } catch {
            profileError = error.localizedDescription
        }
    }
}

#Preview("Light") {
    OnboardingFlow()
}

#Preview("Dark") {
    OnboardingFlow().preferredColorScheme(.dark)
}
