import SwiftUI

/// A small all-caps section header.
///
/// Matches `.section-label` in `design/claude-design-system/ui_kits/mobile/mobile.css`:
/// Inter 11pt, 700 weight, uppercase, 0.1em letter-spacing, `fg-2` color.
///
/// Use above a grouped list or dashboard widget block. Surrounding spacing
/// (22pt top, 10pt bottom per CSS) is the caller's responsibility — apply via
/// `.padding` where it's used.
struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.DS.sans(size: 11, weight: .bold))
            .tracking(1.1)  // 0.1em at 11pt ≈ 1.1pt
            .textCase(.uppercase)
            .foregroundStyle(Color.DS.fg2)
    }
}

#Preview("Light") {
    VStack(alignment: .leading, spacing: 10) {
        SectionLabel("Today's logs")
        SectionLabel("Exercises")
        SectionLabel("Nutrition")
    }
    .padding(32)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.DS.bg1)
}

#Preview("Dark") {
    VStack(alignment: .leading, spacing: 10) {
        SectionLabel("Today's logs")
        SectionLabel("Exercises")
    }
    .padding(32)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}
