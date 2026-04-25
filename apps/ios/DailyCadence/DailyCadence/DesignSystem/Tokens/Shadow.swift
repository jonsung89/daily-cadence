import SwiftUI

/// DailyCadence shadow tokens.
///
/// Light mode: shadows are tinted with warm ink (`#2C2620`) at low opacity so
/// they read warm against the cream background.
/// Dark mode: shadows switch to pure black at much higher opacity — on dark
/// surfaces, warm-tinted shadows disappear; only high-contrast black reads
/// as depth.
///
/// Each level is two stacked shadows to match the layered CSS values in
/// `design/claude-design-system/colors_and_type.css`.
enum DSShadow {
    case level1  // resting cards
    case level2  // floating elements (popovers, bottom sheets)
    case level3  // modals
    case hover   // desktop hover lift
}

extension View {
    /// Apply a design-system shadow layer. Automatically adapts to colorScheme.
    /// Usage: `myCard.dsShadow(.level1)`
    func dsShadow(_ shadow: DSShadow) -> some View {
        modifier(DSShadowModifier(shadow: shadow))
    }
}

private struct DSShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let shadow: DSShadow

    func body(content: Content) -> some View {
        switch (shadow, colorScheme) {
        case (.level1, .light):
            content
                .shadow(color: Self.warmInk(0.04), radius: 2, y: 1)
                .shadow(color: Self.warmInk(0.03), radius: 1, y: 1)
        case (.level1, .dark):
            content
                .shadow(color: Self.black(0.32), radius: 2, y: 1)
                .shadow(color: Self.black(0.24), radius: 1, y: 1)

        case (.level2, .light):
            content
                .shadow(color: Self.warmInk(0.06), radius: 12, y: 4)
                .shadow(color: Self.warmInk(0.04), radius: 2,  y: 1)
        case (.level2, .dark):
            content
                .shadow(color: Self.black(0.40), radius: 12, y: 4)
                .shadow(color: Self.black(0.28), radius: 2,  y: 1)

        case (.level3, .light):
            content
                .shadow(color: Self.warmInk(0.10), radius: 28, y: 12)
                .shadow(color: Self.warmInk(0.05), radius: 6,  y: 2)
        case (.level3, .dark):
            content
                .shadow(color: Self.black(0.48), radius: 28, y: 12)
                .shadow(color: Self.black(0.30), radius: 6,  y: 2)

        case (.hover, .light):
            content
                .shadow(color: Self.warmInk(0.08), radius: 20, y: 8)
                .shadow(color: Self.warmInk(0.04), radius: 4,  y: 2)
        case (.hover, .dark):
            content
                .shadow(color: Self.black(0.42), radius: 20, y: 8)
                .shadow(color: Self.black(0.28), radius: 4,  y: 2)

        @unknown default:
            content
                .shadow(color: Self.warmInk(0.04), radius: 2, y: 1)
                .shadow(color: Self.warmInk(0.03), radius: 1, y: 1)
        }
    }

    private static func warmInk(_ opacity: Double) -> Color {
        Color(hex: 0x2C2620, opacity: opacity)
    }

    private static func black(_ opacity: Double) -> Color {
        Color.black.opacity(opacity)
    }
}
