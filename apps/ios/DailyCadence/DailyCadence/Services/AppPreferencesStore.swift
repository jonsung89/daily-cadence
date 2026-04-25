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

    init(defaults: UserDefaults = .standard) {
        if let raw = defaults.string(forKey: Self.defaultTodayViewKey),
           let mode = Self.parse(raw) {
            self.defaultTodayView = mode
        } else {
            self.defaultTodayView = .timeline
        }
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
