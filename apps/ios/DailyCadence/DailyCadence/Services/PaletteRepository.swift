import Foundation
import OSLog

/// Loads per-note color palettes (Bold / Bright / Pastel / Neutral) from
/// `Resources/palettes.json`.
///
/// The JSON is the source of truth — a future admin panel can edit the file
/// (or overlay remote overrides) without an App Store release. This
/// repository currently reads only the bundled seed; when we wire remote
/// config (Phase F in `docs/PROGRESS.md`), merge remote JSON here before
/// returning.
final class PaletteRepository {
    static let shared = PaletteRepository()

    private let bundle: Bundle
    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "PaletteRepository")

    /// Eagerly loaded at init. Originally a `lazy var`, but Swift's `lazy
    /// var` is not thread-safe — under parallel Swift Testing it raced and
    /// crashed in `outlined destroy of IndexingIterator<[ColorPalette]>`.
    /// JSON decode is fast enough (<5ms) that loading at construction time
    /// is the right tradeoff.
    private let cached: [ColorPalette]

    /// **Phase E.5.21 — synthetic "essentials" swatches.** White + black
    /// don't belong to any of the JSON palettes (we don't want them
    /// appearing as note-background tabs in the BackgroundPickerView),
    /// but the text-color picker should always offer them at the front.
    /// They live here as invariant-color synthetic swatches and are
    /// resolvable by `swatch(id:)` like any other swatch — `TextStyle.colorId`
    /// round-trips through the same path. `allPalettes()` and
    /// `allSwatches()` *do not* include them, so picker surfaces that
    /// iterate by palette/swatch are unaffected unless they explicitly
    /// call `essentialSwatches()`.
    private static let essentials: [Swatch] = [
        Swatch(id: "essentials.white", name: "White", light: "#FFFFFF", dark: "#FFFFFF"),
        Swatch(id: "essentials.black", name: "Black", light: "#000000", dark: "#000000"),
    ]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        self.cached = Self.loadSeed(bundle: bundle)
    }

    /// Every palette, in the order declared in JSON.
    func allPalettes() -> [ColorPalette] {
        cached
    }

    /// Flat list of every swatch across every palette. Useful when a picker
    /// surfaces swatches without their palette grouping. Does **not**
    /// include `essentialSwatches()` — those are only for surfaces that
    /// opt in (e.g. the text-color picker).
    func allSwatches() -> [Swatch] {
        cached.flatMap(\.swatches)
    }

    /// White + black, in that order. The text-color picker shows these
    /// first (after Default) so high-contrast picks are always at hand.
    func essentialSwatches() -> [Swatch] {
        Self.essentials
    }

    /// Look up a swatch by its fully-qualified id. Checks essentials
    /// first (`essentials.white` / `essentials.black`), then the palette
    /// JSON (`neutral.clay`, `bold.cobalt`, etc.).
    func swatch(id: String) -> Swatch? {
        if let essential = Self.essentials.first(where: { $0.id == id }) {
            return essential
        }
        return allSwatches().first { $0.id == id }
    }

    /// Look up a palette by id (e.g. `"bold"`).
    func palette(id: String) -> ColorPalette? {
        cached.first { $0.id == id }
    }

    // MARK: - Loading

    private static func loadSeed(bundle: Bundle) -> [ColorPalette] {
        let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "PaletteRepository")
        guard let url = bundle.url(forResource: "palettes", withExtension: "json") else {
            log.error("palettes.json missing from bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let palettes = try JSONDecoder().decode([ColorPalette].self, from: data)
            log.info("Loaded \(palettes.count) palettes from seed JSON")
            return palettes
        } catch {
            log.error("Failed to decode palettes.json: \(error.localizedDescription)")
            return []
        }
    }
}
