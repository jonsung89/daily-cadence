import SwiftUI

/// A single user-selectable font option.
///
/// Three sources, each resolved to a SwiftUI `Font` differently:
/// - `bundled` — ships as a TTF in `Resources/Fonts/` (Inter, Playfair, etc.).
///   Use `postscriptName` with `Font.custom`.
/// - `iosBuiltIn` — installed on every iOS device (Baskerville, American
///   Typewriter, Noteworthy). Use `postscriptName` with `Font.custom`; no
///   bundling needed.
/// - `system` — SwiftUI system fonts with a design hint (serif / rounded /
///   monospaced). Use `Font.system(size:design:)`; `postscriptName` is ignored.
struct NoteFontDefinition: Decodable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let source: Source
    /// Required when `source` is `bundled` or `iosBuiltIn`. Ignored for `system`.
    let postscriptName: String?
    /// Required when `source` is `system`. One of `serif`, `rounded`,
    /// `monospaced`, `default`.
    let systemDesign: String?

    enum Source: String, Decodable, Hashable {
        case bundled
        case iosBuiltIn
        case system
    }

    /// Build a SwiftUI `Font` at the requested size. Weight can be applied
    /// by the caller via `.weight(_:)`; variable fonts (Inter, Playfair,
    /// Manrope) traverse their `wght` axis automatically.
    func font(size: CGFloat) -> Font {
        switch source {
        case .bundled, .iosBuiltIn:
            if let ps = postscriptName, !ps.isEmpty {
                return Font.custom(ps, size: size)
            }
            return .system(size: size)
        case .system:
            return .system(size: size, design: designHint)
        }
    }

    private var designHint: Font.Design {
        switch systemDesign {
        case "serif":       return .serif
        case "rounded":     return .rounded
        case "monospaced":  return .monospaced
        default:            return .default
        }
    }
}
