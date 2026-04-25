import Foundation
import OSLog

/// Loads user-selectable font options from `Resources/fonts.json`.
///
/// Three sources are supported: bundled (our TTFs), iOS built-in (fonts
/// installed on every iPhone — no bundling cost), and SwiftUI system fonts
/// with a design hint.
final class FontRepository {
    static let shared = FontRepository()

    /// The id of the default font. If the user's saved selection can't be
    /// resolved, fall back to this.
    static let defaultId = "inter"

    private let bundle: Bundle
    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "FontRepository")

    /// Eagerly loaded at init — see PaletteRepository for the rationale
    /// (Swift `lazy var` is not thread-safe under parallel Swift Testing).
    private let cached: [NoteFontDefinition]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        self.cached = Self.loadSeed(bundle: bundle)
    }

    func allFonts() -> [NoteFontDefinition] {
        cached
    }

    func font(id: String) -> NoteFontDefinition? {
        cached.first { $0.id == id }
    }

    func defaultFont() -> NoteFontDefinition {
        guard let font = font(id: Self.defaultId) else {
            assertionFailure("Default font '\(Self.defaultId)' missing from fonts.json")
            return NoteFontDefinition(
                id: "system-fallback",
                displayName: "System",
                source: .system,
                postscriptName: nil,
                systemDesign: "default"
            )
        }
        return font
    }

    // MARK: - Loading

    private static func loadSeed(bundle: Bundle) -> [NoteFontDefinition] {
        let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "FontRepository")
        guard let url = bundle.url(forResource: "fonts", withExtension: "json") else {
            log.error("fonts.json missing from bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let fonts = try JSONDecoder().decode([NoteFontDefinition].self, from: data)
            log.info("Loaded \(fonts.count) fonts from seed JSON")
            return fonts
        } catch {
            log.error("Failed to decode fonts.json: \(error.localizedDescription)")
            return []
        }
    }
}
