import Foundation
import SwiftUI
import Testing
@testable import DailyCadence

/// Verifies `TimelineStore` reads/writes the notes array as expected.
/// The store is the source of truth for the Today timeline; if `add` doesn't
/// mutate the array, the editor flow silently drops new notes.
struct TimelineStoreTests {

    @Test func initialNotesMatchInjectedSeed() {
        let seed = [
            MockNote(occurredAt: .now, type: .mood, content: .text(title: "Test")),
        ]
        let store = TimelineStore(initialNotes: seed)
        #expect(store.notes.count == 1)
        #expect(store.notes.first?.timelineTitle == "Test")
    }

    @Test func emptySeedYieldsEmptyStore() {
        let store = TimelineStore(initialNotes: [])
        #expect(store.notes.isEmpty)
    }

    @Test func addAppendsToTheEnd() {
        let store = TimelineStore(initialNotes: [])
        store.add(MockNote(occurredAt: .now, type: .workout, content: .text(title: "First")))
        store.add(MockNote(occurredAt: .now, type: .meal,    content: .text(title: "Second")))
        #expect(store.notes.count == 2)
        #expect(store.notes[0].timelineTitle == "First")
        #expect(store.notes[1].timelineTitle == "Second")
    }

    @Test func addPreservesContentVariant() {
        // The editor in Phase C only emits .text, but the store should
        // accept any Content variant since real notes (Phase D+) carry
        // stat/list/quote shapes too.
        let store = TimelineStore(initialNotes: [])
        store.add(MockNote(
            occurredAt: .now,
            type: .sleep,
            content: .stat(title: "Slept", value: "7h 30m", sub: nil)
        ))
        guard case let .stat(_, value, _) = store.notes.first?.content else {
            Issue.record("Stat content variant did not round-trip through the store")
            return
        }
        #expect(value == "7h 30m")
    }

    @Test func defaultInitYieldsEmptyAtRuntime() {
        // Phase F.0.2: production launches start empty so a fresh anon user
        // doesn't see other people's mock-seed notes flash on the timeline
        // before NotesRepository.load completes. SwiftUI Previews still seed
        // MockNotes.today via the XCODE_RUNNING_FOR_PREVIEWS env var, but
        // this test runs in xctest, not previews — so the default is empty.
        let store = TimelineStore()
        #expect(store.notes.isEmpty,
                "Default seed at runtime must be empty so first-launch users don't see fake notes flash")
    }

    @Test func attributedMessagePreservesPerRunAttributes() {
        // Phase E.2 — message is AttributedString. A note's per-run font +
        // foreground color must round-trip through the store unchanged so
        // rich-text edits aren't silently flattened on save.
        var attributed = AttributedString("Hello world")
        // Style "world" with Playfair + cobalt-ish color.
        if let worldStart = attributed.range(of: "world") {
            attributed[worldStart].font = .custom("PlayfairDisplay-Regular", size: 16)
            attributed[worldStart].foregroundColor = .red
        }
        let store = TimelineStore(initialNotes: [])
        store.add(MockNote(
            occurredAt: .now,
            type: .mood,
            content: .text(title: "Rich", message: attributed)
        ))

        // Phase E.5.18 — `.text` content body is a `[TextBlock]` list.
        // The convenience constructor wraps a single AttributedString
        // into one `.paragraph` block; we extract it back out for
        // the round-trip assertion.
        guard case let .text(_, body)? = store.notes.first?.content else {
            Issue.record("Expected stored content to be .text")
            return
        }
        guard let firstBlock = body.first,
              case let .paragraph(recovered) = firstBlock.kind else {
            Issue.record("Expected body to start with a paragraph block carrying the message")
            return
        }
        #expect(recovered == attributed,
                "Per-run AttributedString attributes must survive the store add/read round-trip")
    }
}
