import SwiftUI
import Testing
@testable import DailyCadence

/// Verifies `TextStyle` resolution against the font + palette repositories,
/// and that empty styles collapse cleanly when stored on `MockNote`.
struct TextStyleTests {

    // MARK: - Empty / clean

    @Test func emptyStyleIsDetected() {
        #expect(TextStyle().isEmpty)
        #expect(TextStyle(fontId: nil, colorId: nil).isEmpty)
        #expect(!TextStyle(fontId: "inter").isEmpty)
        #expect(!TextStyle(colorId: "bold.cobalt").isEmpty)
    }

    @Test func mockNoteCollapsesEmptyStyleToNil() {
        // Empty TextStyles must not leak into persistence — the init nil-erases them.
        let note = MockNote(
            occurredAt: .now,
            type: .mood,
            content: .text(title: "x"),
            titleStyle: TextStyle()  // empty
        )
        #expect(note.titleStyle == nil)
    }

    @Test func mockNotePreservesNonEmptyStyle() {
        let note = MockNote(
            occurredAt: .now,
            type: .mood,
            content: .text(title: "x"),
            titleStyle: TextStyle(fontId: "playfair", colorId: "bold.cobalt")
        )
        #expect(note.titleStyle?.fontId == "playfair")
        #expect(note.titleStyle?.colorId == "bold.cobalt")
    }

    // MARK: - Resolution against repositories

    @Test func validFontIdResolvesToDefinition() {
        let style = TextStyle(fontId: "playfair")
        let definition = style.resolvedFontDefinition()
        #expect(definition?.id == "playfair")
        #expect(definition?.displayName == "Playfair Display")
    }

    @Test func unknownFontIdResolvesToNil() {
        let style = TextStyle(fontId: "comic-sans-99")
        #expect(style.resolvedFontDefinition() == nil)
    }

    @Test func validColorIdResolvesToSwatch() {
        let style = TextStyle(colorId: "bold.cobalt")
        let swatch = style.resolvedSwatch()
        #expect(swatch?.id == "bold.cobalt")
        #expect(swatch?.name == "Cobalt")
    }

    @Test func unknownColorIdResolvesToNil() {
        let style = TextStyle(colorId: "neon.was-removed")
        #expect(style.resolvedSwatch() == nil)
    }

    // MARK: - Optional binding helpers

    @Test func optionalNilFallsBackToDefaultColor() {
        let style: TextStyle? = nil
        let resolved = style.resolvedColor(default: Color.DS.ink)
        #expect(resolved == Color.DS.ink)
    }

    @Test func optionalEmptyStyleFallsBackToDefaultColor() {
        let style: TextStyle? = TextStyle()
        let resolved = style.resolvedColor(default: Color.DS.fg2)
        #expect(resolved == Color.DS.fg2)
    }

    @Test func styleSurvivesStoreRoundTrip() {
        let store = TimelineStore(initialNotes: [])
        let note = MockNote(
            occurredAt: .now,
            type: .meal,
            content: .text(title: "Styled"),
            titleStyle: TextStyle(fontId: "baskerville", colorId: "bright.coral")
        )
        store.add(note)
        let stored = store.notes.first
        #expect(stored?.titleStyle?.fontId == "baskerville")
        #expect(stored?.titleStyle?.colorId == "bright.coral")
    }
}
