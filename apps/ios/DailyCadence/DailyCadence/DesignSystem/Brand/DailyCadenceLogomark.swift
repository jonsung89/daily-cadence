import SwiftUI

/// The DailyCadence logomark — a soft-radius tile containing an oversized
/// opening double-quote glyph.
///
/// Mirrors `design/claude-design-system/preview/logo.html`:
/// - 33% border-radius on a square tile
/// - Opening left double quote ("\u{201C}")
/// - Glyph font size ≈ 1.03× tile size
/// - Glyph nudged down 0.18em because double quotes sit in the upper half
///   of their em-box — the offset brings the ink center to the tile center
///
/// Glyph is rendered in **Manrope 800** (bundled under
/// `Resources/Fonts/Manrope.ttf`, registered via `FontLoader`).
struct DailyCadenceLogomark: View {
    enum Variant {
        /// Default: sage tile, pale-taupe glyph.
        case sage
        /// Alt: pale-taupe tile, ink glyph — use on sage or ink backgrounds.
        case paleTaupe
    }

    var size: CGFloat = 48
    var variant: Variant = .sage

    var body: some View {
        // RR drives the layout size; the glyph rides as an `.overlay` so
        // its intrinsic line-height (Manrope at 1.03× tile is ~1.2× tile
        // tall) can't pull the tile into a portrait rectangle. Earlier
        // we used a ZStack with a trailing `.frame` — same intent, but
        // the ZStack's own sizing logic still leaked the Text's height
        // into the visible tile when the parent (e.g. an HStack with a
        // shorter sibling) gave it room to grow.
        RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
            .fill(tileColor)
            .frame(width: size, height: size)
            .overlay(
                Text("\u{201C}")
                    .font(.DS.manropeExtraBold(size: size * 1.03))
                    .foregroundStyle(glyphColor)
                    .offset(y: size * 0.185)
            )
            .accessibilityLabel("DailyCadence")
    }

    private var tileColor: Color {
        switch variant {
        case .sage:      return .DS.sage
        case .paleTaupe: return .DS.taupe
        }
    }

    private var glyphColor: Color {
        switch variant {
        case .sage:      return .DS.taupe
        case .paleTaupe: return .DS.ink
        }
    }
}

// MARK: - Previews

#Preview("Size ladder") {
    HStack(alignment: .bottom, spacing: 20) {
        VStack(spacing: 6) {
            DailyCadenceLogomark(size: 16)
            Text("16").font(.caption2).foregroundStyle(Color.DS.fg2)
        }
        VStack(spacing: 6) {
            DailyCadenceLogomark(size: 24)
            Text("24").font(.caption2).foregroundStyle(Color.DS.fg2)
        }
        VStack(spacing: 6) {
            DailyCadenceLogomark(size: 32)
            Text("32").font(.caption2).foregroundStyle(Color.DS.fg2)
        }
        VStack(spacing: 6) {
            DailyCadenceLogomark(size: 48)
            Text("48").font(.caption2).foregroundStyle(Color.DS.fg2)
        }
        VStack(spacing: 6) {
            DailyCadenceLogomark(size: 72)
            Text("72").font(.caption2).foregroundStyle(Color.DS.fg2)
        }
    }
    .padding(32)
    .background(Color.DS.bg1)
}

#Preview("Variants, light") {
    HStack(spacing: 20) {
        DailyCadenceLogomark(size: 88, variant: .sage)
        DailyCadenceLogomark(size: 88, variant: .paleTaupe)
    }
    .padding(32)
    .background(Color.DS.bg1)
}

#Preview("Variants, dark") {
    HStack(spacing: 20) {
        DailyCadenceLogomark(size: 88, variant: .sage)
        DailyCadenceLogomark(size: 88, variant: .paleTaupe)
    }
    .padding(32)
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}
