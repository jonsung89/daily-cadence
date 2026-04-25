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

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        self.cached = Self.loadSeed(bundle: bundle)
    }

    /// Every palette, in the order declared in JSON.
    func allPalettes() -> [ColorPalette] {
        cached
    }

    /// Flat list of every swatch across every palette. Useful when a picker
    /// surfaces swatches without their palette grouping.
    func allSwatches() -> [Swatch] {
        cached.flatMap(\.swatches)
    }

    /// Look up a swatch by its fully-qualified id (e.g. `"neutral.clay"`).
    func swatch(id: String) -> Swatch? {
        allSwatches().first { $0.id == id }
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
