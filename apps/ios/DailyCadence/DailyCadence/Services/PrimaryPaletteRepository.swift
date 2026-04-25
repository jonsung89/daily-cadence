import Foundation
import OSLog

/// Loads primary-color theme swatches (Sage / Blush / Sand / Lavender / Storm
/// / Teal) from `Resources/primary-palettes.json`.
///
/// Each entry ships a hand-tuned trio (`primary` / `deep` / `soft`) × light +
/// dark — 6 hex values per swatch — so the app's accent color reads polished
/// in both appearances no matter which theme the user picks.
final class PrimaryPaletteRepository {
    static let shared = PrimaryPaletteRepository()

    /// The id of the default theme. If the repository fails to load or the
    /// user's saved selection can't be found, this is the fallback.
    static let defaultId = "sage"

    private let bundle: Bundle
    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "PrimaryPaletteRepository")

    /// Eagerly loaded at init — see PaletteRepository for the rationale
    /// (Swift `lazy var` is not thread-safe under parallel Swift Testing).
    private let cached: [PrimarySwatch]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        self.cached = Self.loadSeed(bundle: bundle)
    }

    /// Every primary swatch, in the order declared in JSON.
    func allSwatches() -> [PrimarySwatch] {
        cached
    }

    /// Look up a swatch by id. Returns `nil` if not present.
    func swatch(id: String) -> PrimarySwatch? {
        cached.first { $0.id == id }
    }

    /// The default swatch (sage) — guaranteed non-nil as long as the seed
    /// JSON ships correctly. Crashes in debug if missing to surface ship-broken state.
    func defaultSwatch() -> PrimarySwatch {
        guard let swatch = swatch(id: Self.defaultId) else {
            assertionFailure("Default primary swatch '\(Self.defaultId)' missing from primary-palettes.json")
            // Fallback that keeps the app running in release builds even if
            // the seed is broken: a hardcoded sage equivalent.
            return PrimarySwatch(
                id: "sage-fallback",
                name: "Sage",
                description: nil,
                primary: ColorPair(light: "#5A7B6D", dark: "#7FA594"),
                deep:    ColorPair(light: "#3F5A4F", dark: "#A3C2B4"),
                soft:    ColorPair(light: "#D9E3DD", dark: "#2E3F37")
            )
        }
        return swatch
    }

    // MARK: - Loading

    private static func loadSeed(bundle: Bundle) -> [PrimarySwatch] {
        let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "PrimaryPaletteRepository")
        guard let url = bundle.url(forResource: "primary-palettes", withExtension: "json") else {
            log.error("primary-palettes.json missing from bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let swatches = try JSONDecoder().decode([PrimarySwatch].self, from: data)
            log.info("Loaded \(swatches.count) primary swatches from seed JSON")
            return swatches
        } catch {
            log.error("Failed to decode primary-palettes.json: \(error.localizedDescription)")
            return []
        }
    }
}
