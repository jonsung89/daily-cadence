import SwiftUI

/// Full DailyCadence logo — logomark + wordmark, horizontally.
///
/// For hero contexts (splash, onboarding, settings header). Individual
/// surfaces may prefer using `DailyCadenceLogomark` alone (e.g. nav bar,
/// app icon) or `DailyCadenceWordmark` alone (e.g. email signature).
struct DailyCadenceLogo: View {
    /// Defaults to `.oneWord` — the locked canonical brand. Pass `.twoWord`
    /// only when rendering the historical two-word variant.
    var layout: DailyCadenceWordmark.Layout = .oneWord
    /// Mark size in points. The wordmark scales proportionally.
    var markSize: CGFloat = 56

    var body: some View {
        HStack(spacing: markSize * 0.32) {
            DailyCadenceLogomark(size: markSize)
            DailyCadenceWordmark(layout: layout, size: markSize * 0.54)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("DailyCadence")
    }
}

// MARK: - Previews

#Preview("Logo side-by-side") {
    VStack(alignment: .leading, spacing: 32) {
        VStack(alignment: .leading, spacing: 6) {
            Text("one-word (canonical, locked)")
                .font(.caption2).foregroundStyle(Color.DS.fg2).textCase(.uppercase)
            DailyCadenceLogo(layout: .oneWord, markSize: 56)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("two-word (historical)")
                .font(.caption2).foregroundStyle(Color.DS.fg2).textCase(.uppercase)
            DailyCadenceLogo(layout: .twoWord, markSize: 56)
        }
    }
    .padding(32)
    .background(Color.DS.bg1)
}

#Preview("Hero, dark") {
    DailyCadenceLogo(layout: .oneWord, markSize: 80)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.DS.bg1)
        .preferredColorScheme(.dark)
}
