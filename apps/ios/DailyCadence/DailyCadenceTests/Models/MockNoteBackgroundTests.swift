import Foundation
import Testing
@testable import DailyCadence

/// Verifies that `MockNote.Background` round-trips through the swatch
/// repository correctly, and that stale swatch ids degrade gracefully (the
/// note keeps its data, just loses its background tint).
struct MockNoteBackgroundTests {

    @Test func noteWithoutBackgroundResolvesToNil() {
        let note = MockNote(
            occurredAt: .now,
            type: .mood,
            content: .text(title: "Plain")
        )
        #expect(note.background == nil)
        #expect(note.backgroundSwatch == nil)
    }

    @Test func validSwatchIdResolvesToSwatch() {
        let note = MockNote(
            occurredAt: .now,
            type: .mood,
            content: .text(title: "Tinted"),
            background: .color(swatchId: "pastel.mint")
        )
        let swatch = note.backgroundSwatch
        #expect(swatch != nil)
        #expect(swatch?.id == "pastel.mint")
        #expect(swatch?.name == "Mint")
    }

    @Test func unknownSwatchIdResolvesToNil() {
        // Stale id (e.g., palette JSON updated remotely after the note was
        // saved) should not crash — the note simply loses its background.
        let note = MockNote(
            occurredAt: .now,
            type: .mood,
            content: .text(title: "Stale"),
            background: .color(swatchId: "neutral.was-removed")
        )
        #expect(note.background != nil, "Background still stored on the note")
        #expect(note.backgroundSwatch == nil, "But it can't resolve, so cards render with the type default")
    }

    @Test func swatchFromEachPaletteResolves() {
        // Sanity-check one swatch from each palette so a JSON edit that
        // accidentally drops a palette gets caught in CI.
        let samples = [
            "neutral.clay",
            "pastel.mint",
            "bold.cobalt",
            "bright.coral",
            "classic.red",
        ]
        for id in samples {
            let note = MockNote(
                occurredAt: .now,
                type: .mood,
                content: .text(title: "Sample"),
                background: .color(swatchId: id)
            )
            #expect(note.backgroundSwatch != nil, "Expected '\(id)' to resolve via PaletteRepository")
        }
    }

    @Test func backgroundSurvivesStoreRoundTrip() {
        let store = TimelineStore(initialNotes: [])
        let note = MockNote(
            occurredAt: .now,
            type: .workout,
            content: .text(title: "PR day"),
            background: .color(swatchId: "bold.rust")
        )
        store.add(note)
        let stored = store.notes.first
        #expect(stored?.background == .color(swatchId: "bold.rust"))
        #expect(stored?.backgroundSwatch?.name == "Rust")
    }

    // MARK: - Image background

    @Test func imageBackgroundRoundTripsThroughStore() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])  // PNG signature; not a real image, just bytes
        let imageBg = MockNote.ImageBackground(imageData: bytes, opacity: 0.6)
        let note = MockNote(
            occurredAt: .now,
            type: .mood,
            content: .text(title: "With photo"),
            background: .image(imageBg)
        )

        let store = TimelineStore(initialNotes: [])
        store.add(note)
        let stored = store.notes.first

        guard case .image(let recoveredImg)? = stored?.background else {
            Issue.record("Expected stored note's background to be .image")
            return
        }
        #expect(recoveredImg.imageData == bytes)
        #expect(abs(recoveredImg.opacity - 0.6) < 0.0001)
    }

    @Test func imageOpacityIsClampedToValidRange() {
        let tooHigh = MockNote.ImageBackground(imageData: Data(), opacity: 5.0)
        #expect(tooHigh.opacity == 1.0)

        let tooLow = MockNote.ImageBackground(imageData: Data(), opacity: -2.0)
        #expect(tooLow.opacity == 0.0)
    }

    @Test func resolvedBackgroundStyleForImage() {
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        let note = MockNote(
            occurredAt: .now,
            type: .mood,
            content: .text(title: "Resolves"),
            background: .image(MockNote.ImageBackground(imageData: bytes, opacity: 0.4))
        )
        guard case .image(let data, let opacity) = note.resolvedBackgroundStyle else {
            Issue.record("Expected resolvedBackgroundStyle to be .image")
            return
        }
        #expect(data == bytes)
        #expect(abs(opacity - 0.4) < 0.0001)
    }

    @Test func resolvedBackgroundStyleForColor() {
        let note = MockNote(
            occurredAt: .now,
            type: .workout,
            content: .text(title: "Color"),
            background: .color(swatchId: "neutral.clay")
        )
        guard case .color(let swatch) = note.resolvedBackgroundStyle else {
            Issue.record("Expected resolvedBackgroundStyle to be .color")
            return
        }
        #expect(swatch.id == "neutral.clay")
    }

    @Test func resolvedBackgroundStyleStaleSwatchFallsBackToNone() {
        let note = MockNote(
            occurredAt: .now,
            type: .workout,
            content: .text(title: "Stale"),
            background: .color(swatchId: "neutral.was-removed")
        )
        #expect(note.resolvedBackgroundStyle == .none,
                "Stale id resolution must yield .none so cards render with their type default")
    }

    @Test func resolvedBackgroundStyleNilBackgroundIsNone() {
        let note = MockNote(occurredAt: .now, type: .mood, content: .text(title: "Plain"))
        #expect(note.resolvedBackgroundStyle == .none)
    }
}
