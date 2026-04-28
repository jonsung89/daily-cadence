import Foundation
import Testing
@testable import DailyCadence

/// Phase E.3 — verifies the `MediaPayload` model's normalization rules
/// (aspect-ratio clamping, caption trimming) and that `.media` content
/// round-trips through `TimelineStore` unchanged.
struct MediaPayloadTests {

    private static let stubBytes = Data([0x89, 0x50, 0x4E, 0x47])  // PNG signature; not a real image

    @Test func aspectRatioClampsToMin() {
        let p = MediaPayload(kind: .image, data: Self.stubBytes, aspectRatio: 0.1)
        #expect(p.aspectRatio == 0.4,
                "Aspect ratios under 0.4 should clamp so a tall portrait can't collapse the masonry layout")
    }

    @Test func aspectRatioClampsToMax() {
        let p = MediaPayload(kind: .image, data: Self.stubBytes, aspectRatio: 5.0)
        #expect(p.aspectRatio == 2.5,
                "Aspect ratios over 2.5 should clamp so a panorama doesn't stretch wider than the column")
    }

    @Test func aspectRatioWithinRangeIsPreserved() {
        let p = MediaPayload(kind: .image, data: Self.stubBytes, aspectRatio: 1.5)
        #expect(p.aspectRatio == 1.5)
    }

    @Test func capturedAtPreserved() {
        // Phase F.1.2.exifdate — capture moment surfaces in the viewer's
        // metadata overlay. Default is nil for assets without EXIF /
        // creation metadata.
        let withDate = Date(timeIntervalSince1970: 1_745_786_520)  // 2025-04-27 19:42:00 UTC
        let dated = MediaPayload(
            kind: .image,
            data: Self.stubBytes,
            aspectRatio: 1.0,
            capturedAt: withDate
        )
        #expect(dated.capturedAt == withDate)

        let undated = MediaPayload(kind: .image, data: Self.stubBytes, aspectRatio: 1.0)
        #expect(undated.capturedAt == nil,
                "Default capturedAt is nil so screenshots and metadata-less imports don't render a fake date")
    }

    @Test func captionTrimmedAndEmptyBecomesNil() {
        let allWhitespace = MediaPayload(
            kind: .image,
            data: Self.stubBytes,
            aspectRatio: 1.0,
            caption: "   \n  "
        )
        #expect(allWhitespace.caption == nil,
                "Whitespace-only captions should normalize to nil")

        let trimmed = MediaPayload(
            kind: .image,
            data: Self.stubBytes,
            aspectRatio: 1.0,
            caption: "  Sunrise.  "
        )
        #expect(trimmed.caption == "Sunrise.",
                "Captions are trimmed of leading and trailing whitespace")
    }

    @Test func mediaContentRoundTripsThroughStore() {
        let payload = MediaPayload(
            kind: .video,
            data: Data([0x00, 0x01, 0x02]),
            posterData: Data([0xAA, 0xBB]),
            aspectRatio: 16.0 / 9.0,
            caption: "Reservoir at sunrise"
        )
        let store = TimelineStore(initialNotes: [])
        store.add(MockNote(
            occurredAt: .now,
            type: .activity,
            content: .media(payload)
        ))

        guard case let .media(recovered)? = store.notes.first?.content else {
            Issue.record("Expected stored content to be .media")
            return
        }
        #expect(recovered.kind == .video)
        #expect(recovered.data == payload.data)
        #expect(recovered.posterData == payload.posterData)
        #expect(recovered.aspectRatio == payload.aspectRatio)
        #expect(recovered.caption == "Reservoir at sunrise")
    }

    @Test func timelineTitleFallsBackToTypeLabel() {
        let captionless = MediaPayload(
            kind: .image,
            data: Self.stubBytes,
            aspectRatio: 1.0,
            caption: nil
        )
        let imageNote = MockNote(
            occurredAt: .now,
            type: .general,
            content: .media(captionless)
        )
        #expect(imageNote.timelineTitle == "Photo",
                "A captionless image note's timeline title should default to 'Photo'")

        let videoNote = MockNote(
            occurredAt: .now,
            type: .general,
            content: .media(MediaPayload(kind: .video, data: Self.stubBytes, aspectRatio: 1.0))
        )
        #expect(videoNote.timelineTitle == "Video",
                "A captionless video note's timeline title should default to 'Video'")
    }

    @Test func mediaPayloadAccessor() {
        let payload = MediaPayload(kind: .image, data: Self.stubBytes, aspectRatio: 1.0)
        let note = MockNote(occurredAt: .now, type: .general, content: .media(payload))
        #expect(note.mediaPayload != nil)

        let textNote = MockNote(occurredAt: .now, type: .general, content: .text(title: "x"))
        #expect(textNote.mediaPayload == nil)
    }

    @Test func noteKindReflectsContent() {
        // Phase E.4 — `Kind` derives from Content + media kind. Cards use
        // `isMediaNote` to pick between the text and full-bleed scaffolds.
        let imageNote = MockNote(
            occurredAt: .now,
            type: .general,
            content: .media(MediaPayload(kind: .image, data: Self.stubBytes, aspectRatio: 1.0))
        )
        #expect(imageNote.kind == .photo)
        #expect(imageNote.isMediaNote)

        let videoNote = MockNote(
            occurredAt: .now,
            type: .general,
            content: .media(MediaPayload(kind: .video, data: Self.stubBytes, aspectRatio: 1.0))
        )
        #expect(videoNote.kind == .video)
        #expect(videoNote.isMediaNote)

        let textNote = MockNote(occurredAt: .now, type: .general, content: .text(title: "x"))
        #expect(textNote.kind == .text)
        #expect(!textNote.isMediaNote)

        let listNote = MockNote(
            occurredAt: .now,
            type: .general,
            content: .list(title: "x", items: ["a", "b"])
        )
        #expect(listNote.kind == .text,
                "Non-media content variants (.stat/.list/.quote) all collapse to .text kind for scaffold routing")
        #expect(!listNote.isMediaNote)
    }
}
