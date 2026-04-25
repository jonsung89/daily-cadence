import SwiftUI

/// User-chosen styling for a single text element on a note (title or message).
///
/// Both fields are optional — a `nil` field means "use the slot's default."
/// A note with no styling stores `nil` for the whole `TextStyle`, not a
/// `TextStyle(fontId: nil, colorId: nil)` — convention to keep persistence
/// clean.
///
/// Phase E.1 ships per-field styling (one font + one color per text element).
/// True rich text with per-character runs (bold/italic words inside a paragraph)
/// is deferred to Phase E.2 — that needs `AttributedString` editing which
/// requires iOS 18+ or a UIKit `UITextView` wrap.
struct TextStyle: Hashable, Codable {
    /// Font identifier from `FontRepository` (e.g. `"inter"`, `"playfair"`).
    /// `nil` = use the slot's default font.
    let fontId: String?

    /// Color identifier from `PaletteRepository` (any palette: `"bold.cobalt"`,
    /// `"pastel.mint"`, etc.). `nil` = use the slot's default color.
    let colorId: String?

    init(fontId: String? = nil, colorId: String? = nil) {
        self.fontId = fontId
        self.colorId = colorId
    }

    /// Returns `true` when neither override is set — caller can collapse to
    /// `nil` before persisting.
    var isEmpty: Bool {
        fontId == nil && colorId == nil
    }

    // MARK: - Resolution

    /// Resolves to a `NoteFontDefinition`, or `nil` if no font override or the
    /// id has been removed from the repository.
    func resolvedFontDefinition(
        repository: FontRepository = .shared
    ) -> NoteFontDefinition? {
        guard let fontId else { return nil }
        return repository.font(id: fontId)
    }

    /// Resolves to a `Swatch`, or `nil` if no color override or the id has
    /// been removed from the palette.
    func resolvedSwatch(
        repository: PaletteRepository = .shared
    ) -> Swatch? {
        guard let colorId else { return nil }
        return repository.swatch(id: colorId)
    }
}

extension TextStyle {

    /// Build a SwiftUI `Font` for a text slot — applies the user's font
    /// choice (or falls back to a default) and stamps the slot's intrinsic
    /// weight via the variable-font axis.
    func resolvedFont(
        defaultFontId: String,
        size: CGFloat,
        weight: Font.Weight
    ) -> Font {
        let definition: NoteFontDefinition? =
            resolvedFontDefinition() ?? FontRepository.shared.font(id: defaultFontId)
        let base = definition?.font(size: size) ?? .system(size: size)
        return base.weight(weight)
    }

    /// Resolved color for the text slot, or the provided default.
    func resolvedColor(default fallback: Color) -> Color {
        resolvedSwatch()?.color() ?? fallback
    }
}

extension Optional where Wrapped == TextStyle {

    /// Convenience for view code: `note.titleStyle.font(...)` works whether
    /// or not the note has a `titleStyle`.
    func resolvedFont(
        defaultFontId: String,
        size: CGFloat,
        weight: Font.Weight
    ) -> Font {
        switch self {
        case .none:
            let definition = FontRepository.shared.font(id: defaultFontId)
            let base = definition?.font(size: size) ?? .system(size: size)
            return base.weight(weight)
        case .some(let style):
            return style.resolvedFont(defaultFontId: defaultFontId, size: size, weight: weight)
        }
    }

    func resolvedColor(default fallback: Color) -> Color {
        switch self {
        case .none:                 return fallback
        case .some(let style):      return style.resolvedColor(default: fallback)
        }
    }
}
