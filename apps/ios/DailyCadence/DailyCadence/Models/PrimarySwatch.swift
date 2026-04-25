import SwiftUI

/// A pair of light/dark hex values for a single color role.
///
/// Used inside `PrimarySwatch` for the primary / deep / soft triad. Matches
/// the nested JSON shape:
/// ```json
/// "primary": { "light": "#5A7B6D", "dark": "#7FA594" }
/// ```
struct ColorPair: Decodable, Hashable {
    let light: String
    let dark: String

    /// Resolve to a SwiftUI `Color` that adapts to `colorScheme`.
    func color() -> Color {
        Color(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark
                ? HexParser.parseOrZero(dark)
                : HexParser.parseOrZero(light)
            return UIColor(hex: hex)
        })
    }
}

/// A user-selectable primary-color theme, shipping as a hand-tuned trio.
///
/// Changing the primary color in Settings swaps all three tokens at once:
/// - `primary`: main accent (FAB, primary buttons, selected states)
/// - `deep`: pressed / active-tab state (darker on light, brighter on dark)
/// - `soft`: muted tint for chips and subtle fills
///
/// Everything else — neutrals, semantic note-type pigments, decorative
/// accents (periwinkle / blush / honey) — stays fixed. See `CLAUDE.md`'s
/// "color as data legend" convention.
struct PrimarySwatch: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let primary: ColorPair
    let deep: ColorPair
    let soft: ColorPair
}
