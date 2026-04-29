import SwiftUI
import UserNotifications

/// Reminders page — pre-permission for push notifications. Apple's
/// recommendation is to explain *why* before the system prompt fires;
/// the system prompt only fires once per install, and a denied prompt
/// requires the user to flip the switch in Settings.app to recover.
/// So we explain first, then call `requestAuthorization`.
///
/// The actual reminder *scheduling* (and copy/cadence) lands later —
/// it needs an APNs backend (Edge Function or Next.js) to fire from.
/// Getting permission now opens the gate so the feature can ship
/// without re-prompting.
struct OnboardingRemindersPage: View {
    let pageIndex: Int
    let pageCount: Int
    let onDone: () -> Void

    @State private var inFlight = false

    var body: some View {
        OnboardingChrome(
            pageIndex: pageIndex,
            pageCount: pageCount,
            title: "Stay on track",
            body: "DailyCadence can send a gentle reminder when you haven't logged in a while. No spam, no marketing. Just your own cadence.",
            primaryLabel: inFlight ? "Asking…" : "Enable reminders",
            secondaryLabel: "Maybe later",
            isPrimaryEnabled: !inFlight,
            onPrimary: { Task { await requestPermission() } },
            onSecondary: onDone,
            onSkip: nil
        ) {
            RemindersIllustration()
                .padding(.top, Spacing.s4)
        } control: {
            EmptyView()
        }
    }

    @MainActor
    private func requestPermission() async {
        inFlight = true
        defer { inFlight = false }
        // We don't branch on granted/denied — both outcomes advance to
        // the next page. iOS-side state lives in the system, and we'll
        // surface re-enable prompts in the eventual Reminders settings
        // UI rather than here.
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        onDone()
    }
}
