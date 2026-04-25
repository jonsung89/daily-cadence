import SwiftUI

/// A single color swatch with light- and dark-mode values.
///
/// Matches the JSON shape used in `Resources/palettes.json`:
/// ```json
/// { "id": "bold.rust", "name": "Rust", "light": "#C85A3F", "dark": "#D97556" }
/// ```
///
/// Decodable-only — the JSON is the source of truth, not Swift data. Runtime
/// `color()` helper returns a `colorScheme`-aware SwiftUI `Color` via the
/// existing `dynamicColor` pattern.
struct Swatch: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    /// Light-mode hex string as authored in JSON (`"#RRGGBB"`).
    let light: String
    /// Dark-mode hex string.
    let dark: String

    /// Resolve to a SwiftUI `Color` that adapts to the active `colorScheme`.
    func color() -> Color {
        Color(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark
                ? HexParser.parseOrZero(dark)
                : HexParser.parseOrZero(light)
            return UIColor(hex: hex)
        })
    }
}
