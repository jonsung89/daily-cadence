import SwiftUI
import UIKit

/// Produces a `Color` that auto-resolves to the light or dark hex based on the
/// active `UITraitCollection.userInterfaceStyle`. Used for every token that has
/// a dark-mode counterpart in the design system.
private func dynamicColor(light: UInt32, dark: UInt32) -> Color {
    Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: dark)
            : UIColor(hex: light)
    })
}

extension Color {
    /// DailyCadence color tokens.
    ///
    /// Values mirror the CSS custom properties in
    /// `design/claude-design-system/colors_and_type.css`, including the
    /// `:root[data-theme="dark"]` overrides. Tokens respond automatically to
    /// the environment's `colorScheme` via `UIColor { trait in … }`.
    ///
    /// Keep this file in lockstep with the CSS source of truth.
    enum DS {
        // MARK: - Primary accent (theme-driven)
        //
        // `sage` / `sageDeep` / `sageSoft` are the primary-accent trio. The
        // name is historical — the actual hex values resolve from
        // `ThemeStore.shared.primary`, which defaults to sage green but can
        // be swapped in Settings (Phase B) to any theme from
        // `Resources/primary-palettes.json` (blush, sand, lavender, storm,
        // teal, …).
        //
        // These tokens are computed (`static var`) instead of stored so they
        // pick up theme changes at render time. The Observation framework
        // tracks reads of `ThemeStore.shared.primary` inside view bodies and
        // triggers re-renders when the user selects a new theme.
        static var sage:     Color { ThemeStore.shared.primary.primary.color() }
        static var sageDeep: Color { ThemeStore.shared.primary.deep.color() }
        static var sageSoft: Color { ThemeStore.shared.primary.soft.color() }

        // MARK: - Core palette

        static let cream     = dynamicColor(light: 0xF5F3F0, dark: 0x1A1714)
        static let ink       = dynamicColor(light: 0x2C2620, dark: 0xF5F3F0)
        static let warmGray  = dynamicColor(light: 0x8B8680, dark: 0xA39D94)
        static let taupe     = dynamicColor(light: 0xEAE6E1, dark: 0x2A2520)
        static let taupeDeep = dynamicColor(light: 0xD9D3CB, dark: 0x332D27)

        // MARK: - Accent palette

        static let periwinkle     = dynamicColor(light: 0xCBCADA, dark: 0xA6A4C4)
        static let periwinkleSoft = dynamicColor(light: 0xE6E5EE, dark: 0x2E2D3D)
        static let blush          = dynamicColor(light: 0xF2C9C4, dark: 0xE09A93)
        static let blushSoft      = dynamicColor(light: 0xF9E2DF, dark: 0x3D2B29)
        /// Invariant across light/dark — the only token that doesn't shift.
        static let honey          = Color(hex: 0xE8B86B)

        // MARK: - Semantic note-type pigments
        //
        // Pigments "lift" in dark mode for legibility on dark backgrounds.
        // `-soft` companions flip purpose: in light they're pale tints, in
        // dark they become deep muted fills.

        static let workout      = dynamicColor(light: 0xB05B3B, dark: 0xD47A58)
        static let workoutSoft  = dynamicColor(light: 0xEED7CB, dark: 0x3D2A21)
        static let meal         = dynamicColor(light: 0xC9893A, dark: 0xE2A44E)
        static let mealSoft     = dynamicColor(light: 0xF3E3C3, dark: 0x3B2E1B)
        static let sleep        = dynamicColor(light: 0x3E4A64, dark: 0x7F8FAB)
        static let sleepSoft    = dynamicColor(light: 0xD6DAE3, dark: 0x252B38)
        static let mood         = dynamicColor(light: 0x8B6B85, dark: 0xB494AE)
        static let moodSoft     = dynamicColor(light: 0xE5D9E2, dark: 0x342A33)
        static let activity     = dynamicColor(light: 0x7B8B52, dark: 0xA2B277)
        static let activitySoft = dynamicColor(light: 0xE1E5D0, dark: 0x2B3020)
        // Book — coffee-brown evoking leather binding. Distinct from
        // meal's amber (orange-yellow) and workout's terracotta
        // (red-brown) at small dot sizes; reads as scholarly / quiet.
        static let book         = dynamicColor(light: 0x6B4F3A, dark: 0xA38971)
        static let bookSoft     = dynamicColor(light: 0xEFE7DC, dark: 0x332A22)

        // MARK: - Foreground / background roles
        //
        // Role tokens alias to base tokens so they inherit dynamic behavior
        // automatically. `bg2` and `fgOnAccent` flip to warm near-black tints
        // in dark mode (they don't derive from a single base token).

        static let fg1        = ink
        static let fg2        = warmGray
        static let fgOnAccent = dynamicColor(light: 0xFFFFFF, dark: 0x1A1714)
        static let bg1        = cream
        static let bg2        = dynamicColor(light: 0xFFFFFF, dark: 0x221E1A)
        static let bg3        = taupe
        static let border1    = dynamicColor(light: 0xE3DFD9, dark: 0x2E2822)
        static let border2    = dynamicColor(light: 0xD1CBC2, dark: 0x3D3730)
    }
}
