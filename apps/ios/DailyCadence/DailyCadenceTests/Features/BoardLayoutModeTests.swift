import Testing
@testable import DailyCadence

/// Verifies the `BoardLayoutMode` enum stays stable. The picker UI shows
/// segments in `allCases` declaration order, so accidental reordering would
/// silently change which option lands in which slot.
struct BoardLayoutModeTests {

    @Test func declaredOrderIsStable() {
        let ids = BoardLayoutMode.allCases.map(\.id)
        #expect(ids == [.stacked, .grouped, .free],
                "Segmented control depends on this order — Stack / Group / Free, left to right")
    }

    @Test func everyCaseHasNonEmptyTitle() {
        for mode in BoardLayoutMode.allCases {
            #expect(!mode.title.isEmpty, "BoardLayoutMode '\(mode)' is missing its title")
        }
    }

    @Test func everyCaseHasNonEmptySystemImage() {
        for mode in BoardLayoutMode.allCases {
            #expect(!mode.systemImage.isEmpty,
                    "BoardLayoutMode '\(mode)' is missing its SF Symbol")
        }
    }
}
