import Foundation

/// A named group of swatches (Bold / Bright / Pastel / Neutral).
///
/// Used for per-note background color picking. The design system intentionally
/// groups swatches by "vibe" so the picker UI can present them as tabbed
/// categories rather than one long grid.
struct ColorPalette: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let swatches: [Swatch]
}
