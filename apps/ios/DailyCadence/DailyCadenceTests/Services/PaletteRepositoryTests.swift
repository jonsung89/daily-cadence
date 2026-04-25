import Testing
import UIKit
@testable import DailyCadence

/// Verifies that `palettes.json`, `primary-palettes.json`, and `fonts.json`
/// decode correctly and expose the swatches/fonts the app expects. These
/// tests protect against JSON edits that silently break the app.
struct PaletteRepositoryTests {

    @Test func noteBackgroundPalettesLoadInOrder() {
        let palettes = PaletteRepository.shared.allPalettes()
        // Five named palettes in the order declared in JSON. Classic was
        // added last as the "universal named primaries" fallback for users
        // who think in basic color names instead of designer ones.
        let ids = palettes.map(\.id)
        #expect(ids == ["neutral", "pastel", "bold", "bright", "classic"],
                "Palette order must match the JSON declaration — Settings UI depends on it")
    }

    @Test func everyPaletteHasAReasonableSwatchCount() {
        // Count isn't uniform across palettes — Pastel has extra blush variants
        // by design. Guard against accidental wipes (JSON edit that empties a
        // palette) and against bloat (more than 15 is too many for the picker UI).
        for palette in PaletteRepository.shared.allPalettes() {
            #expect(palette.swatches.count >= 6,
                    "Palette '\(palette.id)' should have at least 6 swatches; got \(palette.swatches.count)")
            #expect(palette.swatches.count <= 15,
                    "Palette '\(palette.id)' has too many swatches (\(palette.swatches.count)) — consider splitting")
        }
    }

    @Test func knownSwatchResolvesByID() {
        let clay = PaletteRepository.shared.swatch(id: "neutral.clay")
        #expect(clay?.name == "Clay")
        #expect(clay?.light == "#B05B3B")
        #expect(clay?.dark == "#D47A58")
    }

    @Test func swatchHexParsesToUIColor() {
        guard let rust = PaletteRepository.shared.swatch(id: "bold.rust") else {
            Issue.record("bold.rust swatch missing from JSON")
            return
        }
        // Round-trip: parse the JSON hex string → UIColor → inspect components.
        let uiColor = UIColor(hex: HexParser.parseOrZero(rust.light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        // 0xC85A3F = R=200, G=90, B=63
        let tolerance: CGFloat = 0.002
        #expect(abs(r - 200.0 / 255.0) < tolerance)
        #expect(abs(g -  90.0 / 255.0) < tolerance)
        #expect(abs(b -  63.0 / 255.0) < tolerance)
    }
}

struct PrimaryPaletteRepositoryTests {

    @Test func primarySwatchesLoadInDeclaredOrder() {
        let swatches = PrimaryPaletteRepository.shared.allSwatches()
        let ids = swatches.map(\.id)
        #expect(ids == ["sage", "blush", "coral", "mulberry", "taupe", "lavender", "storm", "teal"],
                "Primary swatch order must match JSON — settings UI shows them in declared order")
    }

    @Test func defaultSwatchIsSage() {
        let sage = PrimaryPaletteRepository.shared.defaultSwatch()
        #expect(sage.id == "sage")
    }

    @Test func sageTrioMatchesHistoricalDesignSystemValues() {
        // Sage must not drift — it's the fallback every view falls back to
        // when a user's saved theme is missing or corrupted.
        guard let sage = PrimaryPaletteRepository.shared.swatch(id: "sage") else {
            Issue.record("sage primary swatch missing from JSON")
            return
        }
        #expect(sage.primary.light == "#5A7B6D")
        #expect(sage.primary.dark  == "#7FA594")
        #expect(sage.deep.light    == "#3F5A4F")
        #expect(sage.deep.dark     == "#A3C2B4")
        #expect(sage.soft.light    == "#D9E3DD")
        #expect(sage.soft.dark     == "#2E3F37")
    }

    @Test func unknownSwatchReturnsNil() {
        #expect(PrimaryPaletteRepository.shared.swatch(id: "no-such-theme") == nil)
    }
}

struct FontRepositoryTests {

    @Test func allFontsLoad() {
        let fonts = FontRepository.shared.allFonts()
        #expect(fonts.isEmpty == false, "fonts.json must ship at least one font")
    }

    @Test func defaultFontIsInter() {
        let defaultFont = FontRepository.shared.defaultFont()
        #expect(defaultFont.id == "inter")
    }

    @Test func bundledFontsResolveAfterRegistration() {
        FontLoader.registerAll()
        for font in FontRepository.shared.allFonts() where font.source == .bundled {
            guard let ps = font.postscriptName else {
                Issue.record("Bundled font '\(font.id)' missing postscriptName")
                continue
            }
            #expect(UIFont(name: ps, size: 16) != nil,
                    "Bundled font '\(ps)' should resolve after FontLoader.registerAll()")
        }
    }

    @Test func iOSBuiltInFontsAreAvailable() {
        // These PS names are installed on every iOS device — if any fail to
        // resolve, either the PS name is wrong in fonts.json or Apple has
        // changed the bundled font set.
        for font in FontRepository.shared.allFonts() where font.source == .iosBuiltIn {
            guard let ps = font.postscriptName else {
                Issue.record("iosBuiltIn font '\(font.id)' missing postscriptName")
                continue
            }
            #expect(UIFont(name: ps, size: 16) != nil,
                    "iOS built-in font '\(ps)' should resolve on this simulator — verify the PostScript name in fonts.json")
        }
    }
}

struct ThemeStoreTests {

    @Test func defaultsToSageOnFirstLaunch() {
        // Isolated UserDefaults so we don't read production state.
        let defaults = UserDefaults(suiteName: "ThemeStoreTests.defaultsToSage")!
        defaults.removePersistentDomain(forName: "ThemeStoreTests.defaultsToSage")

        let store = ThemeStore(userDefaults: defaults)
        #expect(store.primary.id == "sage")
    }

    @Test func selectPersistsAcrossInstances() {
        let suite = "ThemeStoreTests.selectPersists"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = ThemeStore(userDefaults: defaults)
        #expect(first.select(id: "blush"))
        #expect(first.primary.id == "blush")

        // A fresh instance reading from the same UserDefaults should recover
        // the user's selection.
        let second = ThemeStore(userDefaults: defaults)
        #expect(second.primary.id == "blush")
    }

    @Test func selectWithUnknownIdReturnsFalseAndPreservesCurrent() {
        let suite = "ThemeStoreTests.selectUnknown"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = ThemeStore(userDefaults: defaults)
        let originalId = store.primary.id
        #expect(store.select(id: "no-such-theme") == false)
        #expect(store.primary.id == originalId, "Unknown id must not mutate the current selection")
    }

    @Test func missingStoredIdFallsBackToDefault() {
        let suite = "ThemeStoreTests.missingId"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        // Simulate a stale preference from a removed palette entry.
        defaults.set("theme-that-got-deleted", forKey: "com.jonsung.DailyCadence.primarySwatchId")

        let store = ThemeStore(userDefaults: defaults)
        #expect(store.primary.id == "sage", "Stale ids must fall back to the default swatch, not crash")
    }
}

struct HexParserTests {

    @Test func parsesHashPrefixedValue() {
        #expect(HexParser.parse("#5A7B6D") == 0x5A7B6D)
    }

    @Test func parsesUnprefixedValue() {
        #expect(HexParser.parse("5A7B6D") == 0x5A7B6D)
    }

    @Test func rejectsTooShortInput() {
        #expect(HexParser.parse("#5A7B") == nil)
    }

    @Test func rejectsNonHexCharacters() {
        #expect(HexParser.parse("#ZZZZZZ") == nil)
    }

    @Test func parseOrZeroReturnsBlackForInvalidInput() {
        #expect(HexParser.parseOrZero("garbage") == 0)
    }

    @Test func formatRoundtripsThroughParse() {
        let original: UInt32 = 0xB05B3B
        let formatted = HexParser.format(original)
        #expect(formatted == "#B05B3B")
        #expect(HexParser.parse(formatted) == original)
    }
}
