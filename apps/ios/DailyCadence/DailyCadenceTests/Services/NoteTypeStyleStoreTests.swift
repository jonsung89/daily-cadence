import Foundation
import Testing
@testable import DailyCadence

/// Verifies per-type color override storage, persistence, and graceful
/// handling of stale ids.
struct NoteTypeStyleStoreTests {

    /// Each test uses an isolated UserDefaults suite so we don't read or
    /// pollute the user's real preferences.
    private func makeIsolatedDefaults(suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultStateHasNoOverrides() {
        let store = NoteTypeStyleStore(userDefaults: makeIsolatedDefaults(suite: "NoteTypeStyleStoreTests.default"))
        #expect(store.overrides.isEmpty)
        for type in NoteType.allCases {
            #expect(store.swatch(for: type) == nil)
            #expect(!store.hasOverride(for: type))
        }
    }

    @Test func setSwatchPersistsAcrossInstances() {
        let suite = "NoteTypeStyleStoreTests.persists"
        let defaults = makeIsolatedDefaults(suite: suite)

        let first = NoteTypeStyleStore(userDefaults: defaults)
        first.setSwatchId("bold.cobalt", for: .workout)
        #expect(first.swatch(for: .workout)?.id == "bold.cobalt")
        #expect(first.hasOverride(for: .workout))

        // Fresh instance reading from same defaults must recover the override.
        let second = NoteTypeStyleStore(userDefaults: defaults)
        #expect(second.swatch(for: .workout)?.id == "bold.cobalt")
        #expect(second.hasOverride(for: .workout))
    }

    @Test func setNilClearsOverride() {
        let store = NoteTypeStyleStore(userDefaults: makeIsolatedDefaults(suite: "NoteTypeStyleStoreTests.clear"))
        store.setSwatchId("pastel.mint", for: .meal)
        #expect(store.hasOverride(for: .meal))
        store.setSwatchId(nil, for: .meal)
        #expect(!store.hasOverride(for: .meal))
        #expect(store.swatch(for: .meal) == nil)
    }

    @Test func staleSwatchIdResolvesToNil() {
        let store = NoteTypeStyleStore(userDefaults: makeIsolatedDefaults(suite: "NoteTypeStyleStoreTests.stale"))
        // Direct UserDefaults injection to simulate a saved id that no
        // longer exists in the palette JSON.
        store.setSwatchId("neutral.was-removed", for: .sleep)
        #expect(store.overrides["sleep"] == "neutral.was-removed",
                "Override is still stored — graceful recovery happens at read time, not write time")
        #expect(store.swatch(for: .sleep) == nil,
                "Stale id must resolve to nil so NoteType.color falls back to default")
    }

    @Test func resetAllClearsEveryOverride() {
        let store = NoteTypeStyleStore(userDefaults: makeIsolatedDefaults(suite: "NoteTypeStyleStoreTests.reset"))
        store.setSwatchId("bold.cobalt", for: .workout)
        store.setSwatchId("pastel.mint", for: .meal)
        store.setSwatchId("bright.coral", for: .mood)
        #expect(store.overrides.count == 3)
        store.resetAll()
        #expect(store.overrides.isEmpty)
        #expect(store.swatch(for: .workout) == nil)
        #expect(store.swatch(for: .meal) == nil)
        #expect(store.swatch(for: .mood) == nil)
    }

    @Test func emptyStringClearsOverride() {
        let store = NoteTypeStyleStore(userDefaults: makeIsolatedDefaults(suite: "NoteTypeStyleStoreTests.emptyString"))
        store.setSwatchId("bold.cobalt", for: .workout)
        store.setSwatchId("", for: .workout)
        #expect(!store.hasOverride(for: .workout),
                "Empty-string id should be treated as 'clear,' not stored as a literal empty value")
    }
}
