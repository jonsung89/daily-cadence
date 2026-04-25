import SwiftUI

/// The DailyCadence wordmark.
///
/// Canonical form is **"DailyCadence"** (one word, Playfair Display 500,
/// -0.01em tracking). This is the locked brand — override the design system
/// README's two-word prose convention in favor of the one-word wordmark.
///
/// The `.twoWord` layout ("Daily Cadence") is retained for historical contexts
/// or alternate-treatment experiments. New code should use the default.
///
/// Font: Playfair Display 500 (bundled under `Resources/Fonts/PlayfairDisplay.ttf`,
/// registered via `FontLoader`). Weight axis is driven by `.weight(.medium)` since
/// the variable font exposes `wght` 400–900.
struct DailyCadenceWordmark: View {
    enum Layout {
        /// "Daily Cadence" — historical two-word form. Retained for reference
        /// but not the locked brand.
        case twoWord
        /// "DailyCadence" — canonical, locked brand. Default for new code.
        case oneWord
    }

    var layout: Layout = .oneWord
    var size: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.DS.serif(size: size, weight: .medium))
            .tracking(-0.01 * size)
            .foregroundStyle(Color.DS.fg1)
            .accessibilityLabel("DailyCadence")
    }

    private var text: String {
        switch layout {
        case .twoWord: return "Daily Cadence"
        case .oneWord: return "DailyCadence"
        }
    }
}

// MARK: - Previews

#Preview("Layouts compared") {
    VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 2) {
            Text("one-word (canonical, locked)")
                .font(.caption2)
                .foregroundStyle(Color.DS.fg2)
                .textCase(.uppercase)
            DailyCadenceWordmark(layout: .oneWord, size: 30)
        }
        VStack(alignment: .leading, spacing: 2) {
            Text("two-word (historical)")
                .font(.caption2)
                .foregroundStyle(Color.DS.fg2)
                .textCase(.uppercase)
            DailyCadenceWordmark(layout: .twoWord, size: 30)
        }
    }
    .padding(32)
    .background(Color.DS.bg1)
}

#Preview("Scales") {
    VStack(alignment: .leading, spacing: 12) {
        DailyCadenceWordmark(size: 20)
        DailyCadenceWordmark(size: 24)
        DailyCadenceWordmark(size: 30)
        DailyCadenceWordmark(size: 44)
    }
    .padding(32)
    .background(Color.DS.bg1)
}
