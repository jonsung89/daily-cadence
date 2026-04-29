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
    // Phase F.5.planticons — same colors with the journal-pen
    // growing-plant glyph instead of the opening-quote.
    case plantSage, plantBlush, plantCoral, plantMulberry, plantTaupe, plantLavender, plantStorm, plantTeal

    var id: String { rawValue }

    /// True for the growing-plant variants. Used by the picker to
    /// group sections and by `ThemeIconPreview` to render the right
    /// glyph. (Earlier attempts at procedurally-rendered Sun, Spiral,
    /// and Cursive-d families looked computer-drawn and were dropped;
    /// expanding the family count waits on hand-drawn vector assets
    /// from an illustrator.)
    var isPlant: Bool {
        switch self {
        case .plantSage, .plantBlush, .plantCoral, .plantMulberry,
             .plantTaupe, .plantLavender, .plantStorm, .plantTeal:
            return true
        default:
            return false
        }
    }

    /// The alternate-icon name passed to `UIApplication.setAlternateIconName(_:)`.
    /// Nil means "primary AppIcon" (Sage). Other names MUST match
    /// `CFBundleAlternateIcons` keys in Info.plist + the bundle-root
    /// `<name>@2x.png` / `<name>@3x.png` filenames.
    ///
    /// Note: `.blush` returns `"BlushPink"` (not `"Blush"`) — the
    /// original "Blush" name was permanently cached as blank in
    /// Springboard's OS-level icon cache on Jon's dev device after
    /// early-iteration broken builds. Renaming bypasses the poisoned
    /// cache. Functionally identical icon; just a different lookup key.
    var alternateIconName: String? {
        switch self {
        case .sage: return nil
        case .blush:    return "BlushPink"
        case .coral:    return "Coral"
        case .mulberry: return "Mulberry"
        case .taupe:    return "Taupe"
        case .lavender: return "Lavender"
        case .storm:    return "Storm"
        case .teal:     return "Teal"
        case .plantSage:     return "PlantSage"
        case .plantBlush:    return "PlantBlush"
        case .plantCoral:    return "PlantCoral"
        case .plantMulberry: return "PlantMulberry"
        case .plantTaupe:    return "PlantTaupe"
        case .plantLavender: return "PlantLavender"
        case .plantStorm:    return "PlantStorm"
        case .plantTeal:     return "PlantTeal"
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
        case .plantSage: return "Sage"
        case .plantBlush: return "Blush"
        case .plantCoral: return "Coral"
        case .plantMulberry: return "Mulberry"
        case .plantTaupe: return "Taupe"
        case .plantLavender: return "Lavender"
        case .plantStorm: return "Storm"
        case .plantTeal: return "Teal"
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
        case .sage,     .plantSage:     return Color(hex: 0x5A7B6D)
        case .blush,    .plantBlush:    return Color(hex: 0xE89BB1)
        case .coral,    .plantCoral:    return Color(hex: 0xD67B6F)
        case .mulberry, .plantMulberry: return Color(hex: 0x7D3F4D)
        case .taupe,    .plantTaupe:    return Color(hex: 0x9E9289)
        case .lavender, .plantLavender: return Color(hex: 0x9C8AC0)
        case .storm,    .plantStorm:    return Color(hex: 0x6D8AA1)
        case .teal,     .plantTeal:     return Color(hex: 0x3F7A7C)
        }
    }

    /// Glyph color follows the same per-theme rule the renderer used:
    /// - Most tiles: warm taupe (#EAE6E1) — brand-consistent off-white.
    /// - Blush: near-white (#FAFAFA) — visually reads as white on cool pink
    ///   without tripping Springboard's "low color variety = template
    ///   icon → render blank" heuristic that pure #FFFFFF triggered.
    /// - Taupe theme: ink (#2C2620) — taupe glyph on taupe tile would blend.
    var glyphColor: Color {
        switch self {
        case .blush, .plantBlush: return Color(hex: 0xFAFAFA)
        case .taupe, .plantTaupe: return Color(hex: 0x2C2620)
        default:                   return Color(hex: 0xEAE6E1)
        }
    }
}
