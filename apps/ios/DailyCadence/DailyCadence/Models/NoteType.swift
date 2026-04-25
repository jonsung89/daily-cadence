import SwiftUI

/// The type of a note — drives its semantic color, icon, and (eventually)
/// type-specific form fields in the editor.
///
/// Phase 1 ships the five default types defined in the product spec. Custom
/// user-defined types are Phase 3+.
///
/// The icon mapping uses SF Symbols as a Phase 1 placeholder. The design
/// system ships a custom hand-drawn line icon set in
/// `design/claude-design-system/preview/icons.html` — swap to those once the
/// glyphs are extracted into individual SVGs (see the design system README's
/// "Iconography" section).
enum NoteType: String, CaseIterable, Identifiable, Hashable, Codable {
    case workout
    case meal
    case sleep
    case mood
    case activity

    var id: String { rawValue }

    /// Display title. Sentence case per the design system voice rules.
    var title: String {
        switch self {
        case .workout:  return "Workout"
        case .meal:     return "Meal"
        case .sleep:    return "Sleep"
        case .mood:     return "Mood"
        case .activity: return "Activity"
        }
    }

    /// Full-saturation pigment — used for small dots, icons, and single-line
    /// accents. Never fill large areas.
    ///
    /// Reads through `NoteTypeStyleStore.shared` so user-set per-type
    /// overrides (Settings → Note Types) propagate everywhere the type's
    /// color is shown. Falls back to `defaultColor` when no override is set
    /// or the stored swatch id has been removed from the palette.
    var color: Color {
        NoteTypeStyleStore.shared.swatch(for: self)?.color() ?? defaultColor
    }

    /// The design-system pigment for this type, ignoring any user override.
    /// Use when you specifically need to show "what's the default" — e.g.,
    /// in the Settings reset preview.
    var defaultColor: Color {
        switch self {
        case .workout:  return .DS.workout
        case .meal:     return .DS.meal
        case .sleep:    return .DS.sleep
        case .mood:     return .DS.mood
        case .activity: return .DS.activity
        }
    }

    /// Muted companion for chip fills and timeline lanes.
    var softColor: Color {
        switch self {
        case .workout:  return .DS.workoutSoft
        case .meal:     return .DS.mealSoft
        case .sleep:    return .DS.sleepSoft
        case .mood:     return .DS.moodSoft
        case .activity: return .DS.activitySoft
        }
    }

    /// SF Symbol placeholder name. Replace with the design system's custom
    /// line icons when extracted.
    var systemImage: String {
        switch self {
        case .workout:  return "dumbbell"
        case .meal:     return "fork.knife"
        case .sleep:    return "moon"
        case .mood:     return "heart"
        case .activity: return "figure.walk"
        }
    }
}
