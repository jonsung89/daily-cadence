import Foundation
import SwiftUI
import Testing
@testable import DailyCadence

/// Verifies `TimelineStore` reads/writes the notes array as expected.
/// The store is the source of truth for the Today timeline; if `add` doesn't
/// mutate the array, the editor flow silently drops new notes.
struct TimelineStoreTests {

    @Test @MainActor func currentDayInitialisedToStartOfToday() {
        // Phase F.1.2.midnight — `currentDay` is the observable source
        // of truth for "what is today" so views re-render at midnight.
        let store = TimelineStore(initialNotes: [])
        let expected = Calendar.current.startOfDay(for: .now)
        #expect(store.currentDay == expected,
                "currentDay should initialize to startOfDay(for: .now) so date-aware views render correctly on cold launch")
    }

    @Test @MainActor func isViewingTodayDerivesFromCurrentDay() {
        // Phase F.1.2.midnight — `isViewingToday` compares selectedDate
        // against the observed `currentDay` instead of calling
        // `Calendar.current.isDateInToday(_:)` directly. Verifying the
        // semantic: equality means "viewing today," anything else
        // means "viewing some other day."
        let store = TimelineStore(initialNotes: [])
        #expect(store.isViewingToday,
                "Fresh store with selectedDate == startOfDay(.now) should be viewing today")

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: store.currentDay)!
        store.selectDate(yesterday)
        #expect(!store.isViewingToday,
                "After navigating to a previous day, isViewingToday must flip to false so the Today pill surfaces")
    }

    @Test @MainActor func dayCacheRehydratesNotesOnReturn() {
        // Phase F.1.2.daycache — navigating to a day that's been seen
        // before in this session should hydrate `notes` from the
        // in-memory cache so the empty state doesn't flash. The cache
        // is an initial-render hint, NOT a fetch-skip — `hasLoaded`
        // stays false on hydration so the background refetch still
        // fires and surgically merges any updates.
        let store = TimelineStore(initialNotes: [])
        let today = store.currentDay
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        // Add a note on today — populates the cache for today.
        let todayNote = MockNote(occurredAt: today, type: .mood, content: .text(title: "Today's note"))
        store.add(todayNote)
        #expect(store.notes.count == 1)

        // Navigate to yesterday: cache miss → empty.
        store.selectDate(yesterday)
        #expect(store.notes.isEmpty,
                "First visit to a never-loaded day should clear notes (cache miss)")

        // Return to today: cache HIT → notes restored, no empty flash.
        // hasLoaded stays false so the background refetch still runs.
        store.selectDate(today)
        #expect(store.notes.count == 1,
                "Returning to a previously-loaded day should hydrate notes from cache (no empty flash)")
        #expect(store.notes.first?.timelineTitle == "Today's note")
        #expect(!store.hasLoaded,
                "hasLoaded stays false on hydration so the background refetch still fires — cache is a render hint, not a fetch-skip")
    }

    @Test @MainActor func clearDayCacheDropsAllEntries() {
        // Phase F.1.2.daycache — `clearDayCache()` exists for future
        // auth-change wiring (so user A's cached days don't leak into
        // user B's session). Verifying the contract: after clear,
        // returning to a previously-cached day should NOT have its
        // notes hydrated.
        let store = TimelineStore(initialNotes: [])
        let today = store.currentDay
        store.add(MockNote(occurredAt: today, type: .mood, content: .text(title: "X")))

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        store.selectDate(yesterday)
        store.selectDate(today)
        #expect(store.notes.count == 1, "Sanity check: round-trip rehydrates from cache")

        store.clearDayCache()
        store.selectDate(yesterday)
        store.selectDate(today)
        #expect(store.notes.isEmpty,
                "After clearDayCache(), returning to a previously-cached day should be a cache miss (notes empty until refetch)")
    }

    @Test @MainActor func refreshCurrentDayIsIdempotent() {
        // Same-day call → no-op. Prevents triggering needless animations
        // every time scenePhase becomes .active without a real day change.
        let store = TimelineStore(initialNotes: [])
        let before = store.currentDay
        store.refreshCurrentDay()
        #expect(store.currentDay == before,
                "Calling refreshCurrentDay when nothing has changed should leave currentDay alone")
    }

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

    @Test func addInsertsByOccurredAtAscending() {
        // Phase F.1.2.bug-fix — past-event notes (user picks an earlier
        // time when creating) used to append to the end and only land in
        // their chronological slot after an app refresh. The store now
        // sorts on add to match the server's `order("occurred_at",
        // ascending: true)`.
        let store = TimelineStore(initialNotes: [])
        let nine = Date(timeIntervalSince1970: 9 * 3600)
        let ten = Date(timeIntervalSince1970: 10 * 3600)
        let eleven = Date(timeIntervalSince1970: 11 * 3600)

        store.add(MockNote(occurredAt: ten,    type: .general, content: .text(title: "Ten AM")))
        store.add(MockNote(occurredAt: eleven, type: .general, content: .text(title: "Eleven AM")))
        store.add(MockNote(occurredAt: nine,   type: .general, content: .text(title: "Nine AM (past)")))

        #expect(store.notes.count == 3)
        #expect(store.notes[0].timelineTitle == "Nine AM (past)",
                "A past-event note added last must sort into its chronological slot")
        #expect(store.notes[1].timelineTitle == "Ten AM")
        #expect(store.notes[2].timelineTitle == "Eleven AM")
    }

    @Test func updateRepositionsWhenOccurredAtChanges() {
        // Editing the time of an existing note should move it to the
        // matching chronological slot — same invariant as `add`.
        let nine = Date(timeIntervalSince1970: 9 * 3600)
        let ten = Date(timeIntervalSince1970: 10 * 3600)
        let eleven = Date(timeIntervalSince1970: 11 * 3600)
        let id = UUID()
        let seed: [MockNote] = [
            MockNote(id: id,        occurredAt: ten,    type: .general, content: .text(title: "Original at 10")),
            MockNote(occurredAt: eleven, type: .general, content: .text(title: "Eleven AM")),
        ]
        let store = TimelineStore(initialNotes: seed)
        // Move the 10 AM note back to 9 AM.
        let moved = MockNote(id: id, occurredAt: nine, type: .general, content: .text(title: "Moved to 9"))
        store.update(moved)

        #expect(store.notes.count == 2)
        #expect(store.notes[0].id == id, "The repositioned note must sort to the front")
        #expect(store.notes[0].timelineTitle == "Moved to 9")
        #expect(store.notes[1].timelineTitle == "Eleven AM")
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
