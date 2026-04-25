import SwiftUI
import CoreGraphics

/// Ensures bundled fonts are registered before any `Font.DS` token resolves.
///
/// File-level `let` initializers in Swift run lazily the first time any symbol
/// in the file is touched, so a view reading `Font.DS.body` triggers font
/// loading even in SwiftUI Previews (where `DailyCadenceApp.init` doesn't run).
private let _designSystemFontsRegistered: Void = {
    FontLoader.registerAll()
}()

extension Font {

    /// DailyCadence typography tokens.
    ///
    /// Mirrors the `.dc-*` CSS classes and `--fs-*` size scale in
    /// `design/claude-design-system/colors_and_type.css`.
    ///
    /// Fonts:
    /// - **Playfair Display** (serif) — display / headings / moments of warmth
    /// - **Inter** (sans) — body, UI chrome, labels, numbers
    /// - System monospaced — `mono` only
    ///
    /// Accessing any token for the first time triggers `FontLoader.registerAll()`
    /// so Previews and non-app contexts get real type without extra setup.
    enum DS {
        // MARK: - Display / headings (serif)

        /// 44pt Playfair Display 700 — hero / marketing only.
        public static var display: Font { _ = _designSystemFontsRegistered; return serif(size: 44, weight: .bold) }
        /// 32pt Playfair Display 600.
        public static var h1:      Font { _ = _designSystemFontsRegistered; return serif(size: 32, weight: .semibold) }
        /// 24pt Playfair Display 600.
        public static var h2:      Font { _ = _designSystemFontsRegistered; return serif(size: 24, weight: .semibold) }
        /// 20pt Playfair Display 500.
        public static var h3:      Font { _ = _designSystemFontsRegistered; return serif(size: 20, weight: .medium) }

        // MARK: - Body / UI (sans)

        /// 16pt Inter 400 — minimum body size.
        public static var body:    Font { _ = _designSystemFontsRegistered; return sans(size: 16, weight: .regular) }
        /// 14pt Inter 400 — secondary text.
        public static var small:   Font { _ = _designSystemFontsRegistered; return sans(size: 14, weight: .regular) }
        /// 12pt Inter 400 — micro-labels. Pair with `.textCase(.uppercase)` and
        /// `.tracking(0.06em)` per the `.dc-caption` CSS class.
        public static var caption: Font { _ = _designSystemFontsRegistered; return sans(size: 12, weight: .regular) }
        /// 14pt Inter 500 — form labels and stat labels.
        public static var label:   Font { _ = _designSystemFontsRegistered; return sans(size: 14, weight: .medium) }

        // MARK: - Monospace

        /// 14pt system monospaced — timestamps, code, numeric identifiers.
        public static let mono: Font = .system(size: 14, design: .monospaced)

        // MARK: - Custom-size helpers
        //
        // When a surface needs a non-scale size (e.g. the wordmark's 30pt),
        // reach for these helpers rather than hardcoding `Font.custom` at the
        // call site — keeps font-name drift contained to this file.

        /// Custom-size Playfair Display at the given weight.
        public static func serif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            _ = _designSystemFontsRegistered
            return Font.custom("PlayfairDisplay-Regular", size: size).weight(weight)
        }

        /// Custom-size Inter at the given weight.
        public static func sans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            _ = _designSystemFontsRegistered
            return Font.custom("Inter-Regular", size: size).weight(weight)
        }

        /// Manrope 800 — used exclusively for the logomark's opening-quote
        /// glyph. Do not use for body copy.
        public static func manropeExtraBold(size: CGFloat) -> Font {
            _ = _designSystemFontsRegistered
            return Font.custom("Manrope-ExtraBold", size: size)
        }
    }
}
