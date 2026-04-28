import Foundation
import SwiftUI

/// Phase F.1.2.appicon — represents a user-selectable home-screen icon
/// variant. Each case maps 1:1 to one of the primary theme palettes
/// (`PrimaryPaletteRepository`) so the icon picker can show "the same
/// 8 colors as your theme picker" in a familiar order.
///
/// **Naming contract.** `alternateIconName` returns nil for `.sage`
/// (Sage is the project's primary `AppIcon` set, not an alternate)
/// and the capitalized theme id for the others — these MUST match the
/// `.appiconset` folder names under `Assets.xcassets/` AND the
/// `ASSETCATALOG_COMPILER_ALTERNATE_APP_ICON_NAMES` build setting in
/// the project (`Blush Coral Mulberry Taupe Lavender Storm Teal`).
///
/// **`themeId` contract.** Matches `PrimarySwatch.id` from
/// `Resources/primary-palettes.json` so callers can correlate icon ↔
/// theme without a separate lookup.
enum AppIconChoice: String, CaseIterable, Identifiable, Hashable {
    case sage
    case blush
    case coral
    case mulberry
    case taupe
    case lavender
    case storm
    case teal

    var id: String { rawValue }

    /// The asset-catalog alternate-icon name. Nil means "primary
    /// AppIcon" (Sage). Matches what `UIApplication.setAlternateIconName(_:)`
    /// expects.
    var alternateIconName: String? {
        switch self {
        case .sage: return nil
        case .blush:    return "Blush"
        case .coral:    return "Coral"
        case .mulberry: return "Mulberry"
        case .taupe:    return "Taupe"
        case .lavender: return "Lavender"
        case .storm:    return "Storm"
        case .teal:     return "Teal"
        }
    }

    /// Display name shown under each picker cell.
    var displayName: String {
        switch self {
        case .sage: return "Sage"
        case .blush: return "Blush"
        case .coral: return "Coral"
        case .mulberry: return "Mulberry"
        case .taupe: return "Taupe"
        case .lavender: return "Lavender"
        case .storm: return "Storm"
        case .teal: return "Teal"
        }
    }

    /// Maps the choice back to the primary-theme id used by
    /// `PrimaryPaletteRepository` / `ThemeStore`. Used for the
    /// theme-change → icon-suggest prompt.
    var themeId: String { rawValue }

    /// Reverse lookup for the current alternate-icon name (nil → .sage).
    /// Used at app-launch / picker-open to derive the current selection.
    static func from(alternateIconName: String?) -> AppIconChoice {
        guard let name = alternateIconName else { return .sage }
        return AppIconChoice.allCases.first { $0.alternateIconName == name } ?? .sage
    }

    /// Maps a theme id (`PrimarySwatch.id`) to the matching icon choice.
    /// Used by the theme-change prompt to pre-fill the suggested icon.
    static func from(themeId: String) -> AppIconChoice? {
        AppIconChoice(rawValue: themeId)
    }
}

// MARK: - Visual rendering

extension AppIconChoice {
    /// Tile color hex used by the rendered PNG. Mirrors
    /// `primary-palettes.json` light-primary values exactly so the
    /// picker thumbnail matches what the home-screen icon shows.
    var tileColor: Color {
        switch self {
        case .sage:     return Color(hex: 0x5A7B6D)
        case .blush:    return Color(hex: 0xE89BB1)
        case .coral:    return Color(hex: 0xD67B6F)
        case .mulberry: return Color(hex: 0x7D3F4D)
        case .taupe:    return Color(hex: 0x9E9289)
        case .lavender: return Color(hex: 0x9C8AC0)
        case .storm:    return Color(hex: 0x6D8AA1)
        case .teal:     return Color(hex: 0x3F7A7C)
        }
    }

    /// Glyph color follows the same per-theme rule the renderer used:
    /// - Most tiles: warm taupe (#EAE6E1) — brand-consistent off-white.
    /// - Blush: pure white (#FFFFFF) — taupe was muddy against the cool pink.
    /// - Taupe theme: ink (#2C2620) — taupe glyph on taupe tile would blend.
    var glyphColor: Color {
        switch self {
        case .blush:    return Color(hex: 0xFFFFFF)
        case .taupe:    return Color(hex: 0x2C2620)
        default:        return Color(hex: 0xEAE6E1)
        }
    }
}
