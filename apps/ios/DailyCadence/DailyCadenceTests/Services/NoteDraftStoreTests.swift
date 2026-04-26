import Foundation
import Testing
@testable import DailyCadence

/// Phase E.5.18 — `NoteDraftStore`'s block-list helpers (insertMedia,
/// removeBlock, resizeMediaBlock, updateParagraph) and the
/// single-paragraph compatibility bridge (`message` accessor).
struct NoteDraftStoreTests {

    private static func samplePayload() -> MediaPayload {
        MediaPayload(kind: .image, data: Data([0xFF, 0xD8, 0xFF]), aspectRatio: 1.5)
    }

    @Test func freshDraftStartsWithOneEmptyParagraph() {
        let store = NoteDraftStore()
        #expect(store.body.count == 1)
        #expect(store.body[0].isEmptyParagraph)
        #expect(store.isEmpty)
    }

    @Test func messageBridgeReadsFirstParagraph() {
        let store = NoteDraftStore()
        store.body = [
            .paragraph(AttributedString("hello")),
            .media(Self.samplePayload(), size: .medium),
        ]
        #expect(String(store.message.characters) == "hello")
    }

    @Test func messageBridgeWritesIntoFirstParagraph() {
        let store = NoteDraftStore()
        store.body = [
            .paragraph(AttributedString("old")),
            .media(Self.samplePayload(), size: .small),
        ]
        store.message = AttributedString("new")
        if case .paragraph(let text) = store.body.first?.kind {
            #expect(String(text.characters) == "new")
        } else {
            Issue.record("First block should remain a paragraph after message bridge write")
        }
        // Media block beneath should be untouched.
        #expect(store.body.count == 2)
        #expect(store.body[1].isMedia)
    }

    @Test func messageBridgePrependsParagraphIfNoneExists() {
        // Body that starts with media (no paragraph) — writing through
        // the bridge prepends a fresh paragraph rather than silently
        // overwriting the media block.
        let store = NoteDraftStore()
        store.body = [.media(Self.samplePayload(), size: .large)]
        store.message = AttributedString("typed")
        #expect(store.body.count == 2)
        #expect(store.body[0].isParagraph)
        #expect(store.body[1].isMedia)
    }

    @Test func insertMediaPlacesBeforeTrailingParagraphAndPreservesIt() {
        // Phase E.5.18a — insertMedia maintains the structural invariant
        // [firstP?, media*, trailingParagraph]. Inserting before an
        // existing trailing paragraph keeps it as the trailer (so the
        // trailer TextEditor stays anchored to a stable block).
        let store = NoteDraftStore()
        let intro = TextBlock.paragraph(AttributedString("intro"))
        let trailer = TextBlock.paragraph(AttributedString("outro"))
        store.body = [intro, trailer]

        let returned = store.insertMedia(Self.samplePayload(), size: .medium)
        #expect(store.body.count == 3)
        #expect(store.body[0].id == intro.id)
        #expect(store.body[1].isMedia)
        #expect(store.body[2].id == trailer.id)
        #expect(returned == trailer.id,
                "insertMedia returns the existing trailer id when one already exists")
    }

    @Test func insertMediaIntoMediaOnlyBodyEnsuresLeadingAndTrailingParagraphs() {
        // Defensive — body contains only media (shouldn't happen with
        // the invariant in place, but the helper still recovers).
        // Phase E.5.18b: leading paragraph is prepended too so the
        // messageEditor has a binding target.
        let store = NoteDraftStore()
        store.body = [.media(Self.samplePayload(), size: .small)]
        let trailing = store.insertMedia(Self.samplePayload(), size: .small)
        // Expect: [paragraph, originalMedia, newMedia, paragraph]
        #expect(store.body.count == 4)
        #expect(store.body[0].isEmptyParagraph)
        #expect(store.body[1].isMedia)
        #expect(store.body[2].isMedia)
        #expect(store.body[3].id == trailing)
        #expect(store.body[3].isEmptyParagraph)
    }

    @Test func insertMediaIntoSingleParagraphBodyAddsDistinctTrailingParagraph() {
        // Phase E.5.18b regression: typing into the messageEditor then
        // tapping +image used to produce [media, paragraph(text)] —
        // both message and trailer accessors then resolved to the same
        // block, causing the trailerEditor to mirror the messageEditor's
        // text. Fix: insertMedia ensures a DISTINCT trailing paragraph.
        let store = NoteDraftStore()
        let typed = TextBlock.paragraph(AttributedString("my snack for today"))
        store.body = [typed]

        let trailingId = store.insertMedia(Self.samplePayload(), size: .medium)
        // Expect: [typed, media, freshTrailingParagraph]
        #expect(store.body.count == 3)
        #expect(store.body[0].id == typed.id, "Typed paragraph stays as the leading block")
        #expect(store.body[1].isMedia)
        #expect(store.body[2].id == trailingId)
        #expect(store.body[2].id != typed.id,
                "Trailing paragraph must be distinct from the leading paragraph (duplicate-text bug)")
        #expect(store.body[2].isEmptyParagraph)

        // The bridges must point to different blocks now — no duplicate.
        #expect(String(store.message.characters) == "my snack for today")
        #expect(String(store.trailerMessage.characters) == "")
    }

    @Test func multipleInsertsKeepSingleTrailingParagraph() {
        // Two consecutive insertions should still produce
        // [firstP, media1, media2, trailerP] — not a paragraph between
        // the media blocks.
        let store = NoteDraftStore()
        let intro = TextBlock.paragraph(AttributedString("intro"))
        let trailer = TextBlock.paragraph()
        store.body = [intro, trailer]

        store.insertMedia(Self.samplePayload(), size: .medium)
        store.insertMedia(Self.samplePayload(), size: .large)

        // Expect: [intro, media1, media2, trailer]
        #expect(store.body.count == 4)
        #expect(store.body[0].id == intro.id)
        #expect(store.body[1].isMedia)
        #expect(store.body[2].isMedia)
        #expect(store.body[3].id == trailer.id)
    }

    @Test func trailerMessageReadsLastParagraph() {
        let store = NoteDraftStore()
        store.body = [
            .paragraph(AttributedString("first")),
            .media(Self.samplePayload(), size: .medium),
            .paragraph(AttributedString("last")),
        ]
        #expect(String(store.trailerMessage.characters) == "last")
    }

    @Test func trailerMessageWritesLastParagraph() {
        let store = NoteDraftStore()
        let trailer = TextBlock.paragraph(AttributedString(""))
        store.body = [
            .paragraph(AttributedString("first")),
            .media(Self.samplePayload(), size: .medium),
            trailer,
        ]
        store.trailerMessage = AttributedString("after image")
        if case .paragraph(let text) = store.body.last?.kind {
            #expect(String(text.characters) == "after image")
        } else {
            Issue.record("Last block should still be a paragraph")
        }
    }

    @Test func hasMediaReflectsBodyContents() {
        let store = NoteDraftStore()
        #expect(!store.hasMedia)
        store.body = [.paragraph(AttributedString("x"))]
        #expect(!store.hasMedia)
        store.body.append(.media(Self.samplePayload(), size: .medium))
        #expect(store.hasMedia)
    }

    @Test func removeBlockDeletesAndPreservesNeighbors() {
        let store = NoteDraftStore()
        let p1 = TextBlock.paragraph(AttributedString("a"))
        let m  = TextBlock.media(Self.samplePayload(), size: .large)
        let p2 = TextBlock.paragraph(AttributedString("b"))
        store.body = [p1, m, p2]
        store.removeBlock(id: m.id)
        #expect(store.body.count == 2)
        #expect(store.body[0].id == p1.id)
        #expect(store.body[1].id == p2.id)
    }

    @Test func removeBlockRestoresEmptyParagraphIfBodyWouldBeEmpty() {
        let store = NoteDraftStore()
        let only = TextBlock.media(Self.samplePayload(), size: .medium)
        store.body = [only]
        store.removeBlock(id: only.id)
        #expect(store.body.count == 1)
        #expect(store.body[0].isEmptyParagraph,
                "Removing the last block must restore an empty paragraph so the editor still has a cursor target")
    }

    @Test func resizeMediaBlockUpdatesSize() {
        let store = NoteDraftStore()
        let m = TextBlock.media(Self.samplePayload(), size: .small)
        store.body = [m]
        store.resizeMediaBlock(id: m.id, to: .large)
        if case .media(_, let size) = store.body.first?.kind {
            #expect(size == .large)
        } else {
            Issue.record("Block should still be media after resize")
        }
    }

    @Test func resizeOnParagraphIsNoOp() {
        let store = NoteDraftStore()
        let p = TextBlock.paragraph(AttributedString("text"))
        store.body = [p]
        store.resizeMediaBlock(id: p.id, to: .large)
        if case .paragraph = store.body.first?.kind {
            // OK — paragraph untouched.
        } else {
            Issue.record("Paragraph should not be replaced by a resize call")
        }
    }

    @Test func updateParagraphMutatesText() {
        let store = NoteDraftStore()
        let p = TextBlock.paragraph(AttributedString("first"))
        store.body = [p]
        store.updateParagraph(id: p.id, to: AttributedString("second"))
        if case .paragraph(let text) = store.body.first?.kind {
            #expect(String(text.characters) == "second")
        } else {
            Issue.record("Block should still be paragraph after updateParagraph")
        }
    }

    @Test func clearResetsBodyToSingleEmptyParagraph() {
        let store = NoteDraftStore()
        store.body = [
            .paragraph(AttributedString("typed")),
            .media(Self.samplePayload(), size: .large),
        ]
        store.title = "title"
        store.clear()
        #expect(store.title.isEmpty)
        #expect(store.body.count == 1)
        #expect(store.body[0].isEmptyParagraph)
        #expect(store.isEmpty)
    }
}
