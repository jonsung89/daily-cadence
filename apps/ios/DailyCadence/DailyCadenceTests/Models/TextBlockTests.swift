import Foundation
import Testing
@testable import DailyCadence

/// Phase E.5.18 — verifies `TextBlock` + `MockNote.Content.text(body:)`
/// behave as the journal-style block model intends.
struct TextBlockTests {

    private static func samplePayload() -> MediaPayload {
        MediaPayload(kind: .image, data: Data([0xFF, 0xD8, 0xFF]), aspectRatio: 1.5)
    }

    @Test func blockIdentityIsStableAcrossKindEdits() {
        // The Identifiable id stays the same when the wrapped kind is
        // mutated (text edit, size change). SwiftUI's ForEach relies on
        // this for smooth diffing.
        var block = TextBlock.paragraph(AttributedString("Hello"))
        let originalId = block.id
        block.kind = .paragraph(AttributedString("Updated"))
        #expect(block.id == originalId)
    }

    @Test func emptyParagraphDetection() {
        let empty = TextBlock.paragraph()
        let nonEmpty = TextBlock.paragraph(AttributedString("typed"))
        let media = TextBlock.media(Self.samplePayload(), size: .medium)
        #expect(empty.isEmptyParagraph)
        #expect(!nonEmpty.isEmptyParagraph)
        #expect(!media.isEmptyParagraph)
    }

    @Test func paragraphAndMediaPredicates() {
        let paragraph = TextBlock.paragraph()
        let media = TextBlock.media(Self.samplePayload(), size: .small)
        #expect(paragraph.isParagraph)
        #expect(!paragraph.isMedia)
        #expect(media.isMedia)
        #expect(!media.isParagraph)
    }

    @Test func blockBodyRoundTripsThroughTimelineStore() {
        // The full block list — including a media block sandwiched
        // between two paragraphs — must survive `TimelineStore.add`.
        let p1 = TextBlock.paragraph(AttributedString("Felt strong"))
        let m  = TextBlock.media(Self.samplePayload(), size: .large)
        let p2 = TextBlock.paragraph(AttributedString("Hit a PR"))
        let note = MockNote(
            time: "9:00 AM",
            type: .workout,
            content: .text(title: "Workout", body: [p1, m, p2])
        )
        let store = TimelineStore(initialNotes: [])
        store.add(note)

        guard case let .text(_, recovered)? = store.notes.first?.content else {
            Issue.record("Expected stored content to be .text")
            return
        }
        #expect(recovered.count == 3)
        #expect(recovered[0].id == p1.id)
        #expect(recovered[1].id == m.id)
        #expect(recovered[2].id == p2.id)
        if case .media(_, let size) = recovered[1].kind {
            #expect(size == .large, "Media block size must round-trip")
        } else {
            Issue.record("Middle block should be .media")
        }
    }

    @Test func backwardCompatConstructorWrapsMessageInOneParagraph() {
        // Phase E.5.18 added `.text(title:message:)` as a convenience
        // alongside the new `.text(title:body:)`. Calling with a message
        // produces a single-paragraph body — keeps existing seed data
        // and tests working unchanged.
        let note = MockNote(
            time: "9:00 AM",
            type: .general,
            content: .text(title: "x", message: AttributedString("hello"))
        )
        guard case .text(_, let body) = note.content else {
            Issue.record("Expected .text content")
            return
        }
        #expect(body.count == 1)
        if case .paragraph(let text) = body.first?.kind {
            #expect(String(text.characters) == "hello")
        } else {
            Issue.record("First block should be a paragraph")
        }
    }

    @Test func backwardCompatConstructorWithoutMessageProducesEmptyBody() {
        let note = MockNote(
            time: "9:00 AM",
            type: .general,
            content: .text(title: "x")
        )
        guard case .text(_, let body) = note.content else {
            Issue.record("Expected .text content")
            return
        }
        #expect(body.isEmpty,
                "A title-only note carries no paragraph blocks; body is empty")
    }

    @Test func timelineMessageFlattensParagraphBlocksDroppingMedia() {
        // For Timeline rail rendering, a multi-block body collapses to
        // a single AttributedString that concatenates all paragraph text
        // (separated by spaces). Inline media blocks are skipped — the
        // rail is dense, full inline rendering happens on the Board card.
        let note = MockNote(
            time: "9:00 AM",
            type: .workout,
            content: .text(title: "x", body: [
                .paragraph(AttributedString("First")),
                .media(Self.samplePayload(), size: .medium),
                .paragraph(AttributedString("Second")),
            ])
        )
        let timeline = note.timelineMessage
        #expect(timeline != nil)
        #expect(String(timeline!.characters) == "First Second")
    }

    @Test func timelineMessageReturnsNilForBodyWithOnlyMediaOrEmpty() {
        let onlyMedia = MockNote(
            time: "9:00 AM",
            type: .workout,
            content: .text(title: "x", body: [.media(Self.samplePayload(), size: .medium)])
        )
        let empty = MockNote(time: "9:00 AM", type: .general, content: .text(title: "x"))
        #expect(onlyMedia.timelineMessage == nil)
        #expect(empty.timelineMessage == nil)
    }

    @Test func mediaBlockSizeWidthFractionsOrderSmallMediumLarge() {
        // Defensive: makes sure a future tweak of the fractions keeps
        // small < medium < large so cards render as the user expects.
        #expect(MediaBlockSize.small.widthFraction < MediaBlockSize.medium.widthFraction)
        #expect(MediaBlockSize.medium.widthFraction < MediaBlockSize.large.widthFraction)
        #expect(MediaBlockSize.large.widthFraction == 1.0)
    }
}
