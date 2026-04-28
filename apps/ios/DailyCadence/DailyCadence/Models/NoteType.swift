import SwiftUI

/// The type of a note — drives its semantic color, icon, and (eventually)
/// type-specific form fields in the editor.
///
/// Phase 1 ships the five default category types defined in the product
/// spec, plus `.general` (neutral default for text notes; Phase E.2.3) and
/// `.media` (auto-assigned to bare photo/video notes; Phase E.5.10).
/// Custom user-defined types are Phase 3+.
///
/// **Why `.general`.** Without a default neutral type, the editor had to
/// pre-select one of the five category types (we chose `.mood`), which
/// implicitly tagged every quickly-typed note as a Mood. `.general` lets
/// users start typing without committing to a category and opt into one
/// later. It uses warm-gray pigment + taupe soft color so neutral notes
/// don't fight the colored ones on the timeline.
///
/// **Why `.media`.** Bare photo/video notes don't carry a meaningful
/// category — the asset *is* the substance. Forcing the user to pick a
/// type just to log a photo was friction. `.media` auto-tags every
/// `MediaNoteEditorScreen` save so Group/Stack views naturally collect
/// them in their own section. If the user wants semantic context with a
/// photo (e.g., "great workout" + photo), the canonical pattern is a text
/// note with an attached image — once inline-attachments-in-text-notes
/// ships (deferred follow-up).
///
/// `.general` is declared **first** in `allCases` so pickers list it as
/// the default option; `.media` is declared **last** so the type-picker
/// row in `NoteEditorScreen` keeps its existing visual order for the five
/// category types.
///
/// The icon mapping uses SF Symbols as a Phase 1 placeholder. The design
/// system ships a custom hand-drawn line icon set in
/// `design/claude-design-system/preview/icons.html` — swap to those once the
/// glyphs are extracted into individual SVGs (see the design system README's
/// "Iconography" section).
enum NoteType: String, CaseIterable, Identifiable, Hashable, Codable {
    case general
    case workout
    case meal
    case sleep
    case mood
    case activity
    case pets
    case book
    case recipe
    case media

    var id: String { rawValue }

    /// Cases the user can pick as the *type* of a text note. Excludes
    /// `.media`, which is auto-assigned by `MediaNoteEditorScreen` and
    /// would be misleading on a text note (a text note isn't media).
    /// Group / Stack views, Settings → Note Types, and other surfaces
    /// that iterate `allCases` continue to show `.media` like any
    /// other category.
    static var textEditorPickable: [NoteType] {
        allCases.filter { $0 != .media }
    }

    /// Display title. Sentence case per the design system voice rules.
    var title: String {
        switch self {
        case .general:  return "General"
        case .workout:  return "Workout"
        case .meal:     return "Meal"
        case .sleep:    return "Sleep"
        case .mood:     return "Mood"
        case .activity: return "Activity"
        case .pets:     return "Pets"
        case .book:     return "Book"
        case .recipe:   return "Recipe"
        case .media:    return "Media"
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
        case .general:  return .DS.warmGray
        case .workout:  return .DS.workout
        case .meal:     return .DS.meal
        case .sleep:    return .DS.sleep
        case .mood:     return .DS.mood
        case .activity: return .DS.activity
        case .pets:     return .DS.blush
        case .book:     return .DS.book
        case .recipe:   return .DS.recipe
        case .media:    return .DS.periwinkle
        }
    }

    /// Muted companion for chip fills and timeline lanes.
    var softColor: Color {
        switch self {
        case .general:  return .DS.taupe
        case .workout:  return .DS.workoutSoft
        case .meal:     return .DS.mealSoft
        case .sleep:    return .DS.sleepSoft
        case .mood:     return .DS.moodSoft
        case .activity: return .DS.activitySoft
        case .pets:     return .DS.blushSoft
        case .book:     return .DS.bookSoft
        case .recipe:   return .DS.recipeSoft
        case .media:    return .DS.periwinkleSoft
        }
    }

    /// **Phase E.5.22 — scheme-aware tint opacity.** When a card has no
    /// user-picked background, KeepCard tints the surface with the
    /// type's pigment as a calm visual cue. In light mode 0.333 over
    /// the cream surface produces a soft pastel; in dark mode the same
    /// opacity over the dark surface read as muddy because the type
    /// `dark` hexes are lifted/saturated for legibility on dark text.
    ///
    /// **E.5.22a:** dark-mode tint dropped to **0.10** — barely a hint.
    /// The dot + uppercase label already carry the type identity
    /// strongly; the card body should stay close to neutral dark to
    /// avoid the muddy mid-tone problem. Apple Notes / Bear effectively
    /// do this (zero card-fill tinting in dark mode) — 0.10 keeps a
    /// trace of color without the heaviness.
    static func defaultTintOpacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.90 : 0.6
    }

    /// SF Symbol placeholder name. Replace with the design system's custom
    /// line icons when extracted.
    var systemImage: String {
        switch self {
        case .general:  return "note.text"
        case .workout:  return "dumbbell"
        case .meal:     return "fork.knife"
        case .sleep:    return "moon"
        case .mood:     return "heart"
        case .activity: return "figure.walk"
        case .pets:     return "pawprint.fill"
        case .book:     return "book.closed.fill"
        case .recipe:   return "frying.pan.fill"
        case .media:    return "photo.on.rectangle"
        }
    }
}
