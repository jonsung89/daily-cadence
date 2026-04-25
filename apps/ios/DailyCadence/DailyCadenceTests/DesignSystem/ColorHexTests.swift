import Testing
import SwiftUI
import UIKit
@testable import DailyCadence

/// Verifies that `Color(hex:)`, `UIColor(hex:)`, and the `Color.DS` tokens
/// produce the exact RGB values specified by the Claude Design System
/// (`design/claude-design-system/colors_and_type.css`) in both light and dark
/// appearances. Any drift here means the app shows different colors than the
/// handoff.
struct ColorHexTests {

    /// Tolerance for float comparisons on 8-bit color components (≈ 0.5 / 255).
    private let tolerance: CGFloat = 0.002

    // MARK: - Color(hex:) raw initializer

    @Test func colorHexPureBlack() {
        let (r, g, b, a) = components(of: Color(hex: 0x000000))
        #expect(abs(r - 0.0) < tolerance)
        #expect(abs(g - 0.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance)
        #expect(abs(a - 1.0) < tolerance)
    }

    @Test func colorHexPureWhite() {
        let (r, g, b, _) = components(of: Color(hex: 0xFFFFFF))
        #expect(abs(r - 1.0) < tolerance)
        #expect(abs(g - 1.0) < tolerance)
        #expect(abs(b - 1.0) < tolerance)
    }

    @Test func colorHexMixedValue() {
        // 0xFF8040 → R=255, G=128, B=64
        let (r, g, b, _) = components(of: Color(hex: 0xFF8040))
        #expect(abs(r - 255.0 / 255.0) < tolerance)
        #expect(abs(g - 128.0 / 255.0) < tolerance)
        #expect(abs(b -  64.0 / 255.0) < tolerance)
    }

    @Test func colorHexAppliesOpacity() {
        let (_, _, _, a) = components(of: Color(hex: 0x000000, opacity: 0.5))
        #expect(abs(a - 0.5) < tolerance)
    }

    // MARK: - UIColor(hex:) raw initializer

    @Test func uiColorHexMatchesComponents() {
        // 0xB05B3B = R=176, G=91, B=59 — clay pigment
        let ui = UIColor(hex: 0xB05B3B)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 176.0 / 255.0) < tolerance)
        #expect(abs(g -  91.0 / 255.0) < tolerance)
        #expect(abs(b -  59.0 / 255.0) < tolerance)
        #expect(abs(a - 1.0) < tolerance)
    }

    // MARK: - Core palette — light mode

    @Test func creamLightMatchesCSS() {
        // #F5F3F0 = R=245, G=243, B=240
        assertRGB(Color.DS.cream, mode: .light, expected: (245, 243, 240))
    }

    @Test func sageLightMatchesCSS() {
        // #5A7B6D = R=90, G=123, B=109
        assertRGB(Color.DS.sage, mode: .light, expected: (90, 123, 109))
    }

    @Test func inkLightMatchesCSS() {
        // #2C2620 = R=44, G=38, B=32
        assertRGB(Color.DS.ink, mode: .light, expected: (44, 38, 32))
    }

    @Test func workoutLightMatchesCSS() {
        // #B05B3B clay, not the wireframe's brighter #C85A54 terracotta.
        assertRGB(Color.DS.workout, mode: .light, expected: (176, 91, 59))
    }

    // MARK: - Core palette — dark mode

    @Test func creamDarkFlipsToWarmNearBlack() {
        // #1A1714 = R=26, G=23, B=20 — warm near-black surface
        assertRGB(Color.DS.cream, mode: .dark, expected: (26, 23, 20))
    }

    @Test func inkDarkFlipsToWarmOffWhite() {
        // #F5F3F0 = R=245, G=243, B=240 — text flips to cream
        assertRGB(Color.DS.ink, mode: .dark, expected: (245, 243, 240))
    }

    @Test func sageDarkLifts() {
        // #7FA594 = R=127, G=165, B=148 — lifted sage for dark legibility
        assertRGB(Color.DS.sage, mode: .dark, expected: (127, 165, 148))
    }

    @Test func workoutDarkLifts() {
        // #D47A58 = R=212, G=122, B=88 — clay lifted for dark
        assertRGB(Color.DS.workout, mode: .dark, expected: (212, 122, 88))
    }

    @Test func bg2DarkFlipsFromWhiteToCardSurface() {
        // Light: pure white (#FFFFFF). Dark: #221E1A card surface.
        assertRGB(Color.DS.bg2, mode: .dark, expected: (34, 30, 26))
    }

    @Test func fgOnAccentDarkFlipsToNearBlack() {
        // Light: pure white (#FFFFFF). Dark: #1A1714.
        assertRGB(Color.DS.fgOnAccent, mode: .dark, expected: (26, 23, 20))
    }

    // MARK: - Invariants

    @Test func honeyIsInvariantAcrossModes() {
        // #E8B86B — the one token that does not change in dark mode.
        assertRGB(Color.DS.honey, mode: .light, expected: (232, 184, 107))
        assertRGB(Color.DS.honey, mode: .dark,  expected: (232, 184, 107))
    }

    // MARK: - Helpers

    private func components(of color: Color) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    /// Resolve a `Color` against a specific interface style and assert its
    /// 8-bit RGB components match the expected CSS value.
    private func assertRGB(
        _ color: Color,
        mode: UIUserInterfaceStyle,
        expected: (r: Int, g: Int, b: Int),
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let resolved = UIColor(color).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: mode)
        )
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - CGFloat(expected.r) / 255.0) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(g - CGFloat(expected.g) / 255.0) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(b - CGFloat(expected.b) / 255.0) < tolerance, sourceLocation: sourceLocation)
    }
}
