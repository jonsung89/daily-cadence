import Foundation
import SwiftUI

/// User-tunable defaults for app behavior — Phase E.5.
///
/// Distinct from `ThemeStore` (visual theme) and `NoteTypeStyleStore`
/// (per-type color overrides): this is for *behavioral* preferences like
/// "which view does Today open in." Storage is `UserDefaults` so values
/// survive app relaunches without needing iCloud sync.
///
/// Keep this small — every key lives behind a typed property that reads
/// the raw value with a sensible fallback. Stale or unparseable values
/// fall back to the documented default rather than throwing or asserting.
@Observable
final class AppPreferencesStore {
    static let shared = AppPreferencesStore()

    private static let defaultTodayViewKey = "DailyCadence.defaultTodayView"

    /// The view mode the Today screen should open in. Defaults to
    /// `.timeline` — the chronological rail is the spec-ordained default
    /// surface.
    var defaultTodayView: TimelineViewMode = .timeline {
        didSet {
            UserDefaults.standard.set(
                rawValue(defaultTodayView),
                forKey: Self.defaultTodayViewKey
            )
        }
    }

    // MARK: - App icon (Phase F.1.2.appicon)

    private static let iconSyncPromptDismissedKey = "DailyCadence.iconSyncPromptDismissed"

    /// True once the user picked **"Don't ask again"** on the
    /// theme-change → icon-suggest prompt. When true, `ThemeStore`
    /// silently skips the prompt on subsequent theme changes; the user
    /// can still pick an icon manually via Settings → App Icon, and
    /// can re-enable the prompt from the same screen.
    var iconSyncPromptDismissed: Bool = false {
        didSet {
            UserDefaults.standard.set(iconSyncPromptDismissed, forKey: Self.iconSyncPromptDismissedKey)
        }
    }

    // MARK: - Onboarding (Phase F.3.onboarding)

    private static let hasCompletedOnboardingKey = "DailyCadence.hasCompletedOnboarding"

    /// True once the user has reached the Done page of the onboarding
    /// flow at least once on this device. RootView's gate uses this to
    /// decide whether to show the onboarding flow or the main app
    /// shell on launch. Quitting mid-flow leaves this false so users
    /// resume from the start on next launch — intentional, the flow is
    /// short and skipping is supported, no need for partial state
    /// recovery.
    var hasCompletedOnboarding: Bool = false {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.hasCompletedOnboardingKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        if let raw = defaults.string(forKey: Self.defaultTodayViewKey),
           let mode = Self.parse(raw) {
            self.defaultTodayView = mode
        } else {
            self.defaultTodayView = .timeline
        }
        self.iconSyncPromptDismissed = defaults.bool(forKey: Self.iconSyncPromptDismissedKey)
        self.hasCompletedOnboarding = defaults.bool(forKey: Self.hasCompletedOnboardingKey)
    }

    // MARK: - Codec

    private func rawValue(_ mode: TimelineViewMode) -> String {
        switch mode {
        case .timeline: return "timeline"
        case .board:    return "board"
        }
    }

    private static func parse(_ raw: String) -> TimelineViewMode? {
        switch raw {
        case "timeline": return .timeline
        case "board":    return .board
        default:         return nil
        }
    }
}
