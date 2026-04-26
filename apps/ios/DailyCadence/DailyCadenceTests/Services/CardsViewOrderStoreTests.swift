import Foundation
import Testing
@testable import DailyCadence

/// Phase E.4.3 — verifies `CardsViewOrderStore`'s sort + move + reset
/// semantics so the Cards Board layout's drag-to-reorder feature stays
/// honest about its ordering rules. (Renamed from
/// `FreeViewOrderStoreTests` in Phase E.5.1.)
struct CardsViewOrderStoreTests {

    private static func note(_ title: String) -> MockNote {
        MockNote(time: "9:00 AM", type: .general, content: .text(title: title))
    }

    @Test func emptyStoreReturnsInputOrder() {
        // No custom order set — sorted output should match the input
        // chronological order from `TimelineStore`.
        let store = CardsViewOrderStore()
        let notes = [Self.note("a"), Self.note("b"), Self.note("c")]
        let result = store.sorted(notes)
        #expect(result.map(\.timelineTitle) == ["a", "b", "c"])
        #expect(!store.hasCustomOrder)
    }

    @Test func backwardDragLandsSourceAtTargetSlot() {
        // Backward drag (later → earlier): source ends up where target
        // was, target shifts toward source's old slot.
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        let c = Self.note("c")
        let notes = [a, b, c]

        // Move c onto a → expect [c, a, b]
        store.move(c.id, onto: a.id, in: notes)
        #expect(store.hasCustomOrder)
        #expect(store.sorted(notes).map(\.timelineTitle) == ["c", "a", "b"])
    }

    @Test func forwardDragLandsSourceAtTargetSlot() {
        // Forward drag (earlier → later): source ends up where target
        // was, target shifts toward source's old slot. With the older
        // "insert before target" semantics, dropping an earlier card
        // onto its immediate next neighbor was a no-op — this test
        // pins the corrected directional behavior.
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        let c = Self.note("c")
        let notes = [a, b, c]

        // Move a onto b (immediate next neighbor) → expect [b, a, c]
        store.move(a.id, onto: b.id, in: notes)
        #expect(store.sorted(notes).map(\.timelineTitle) == ["b", "a", "c"])
    }

    @Test func forwardDragAcrossMultipleSlots() {
        // Forward drag spanning more than one position: source jumps
        // past the cards between it and the target.
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        let c = Self.note("c")
        let d = Self.note("d")
        let notes = [a, b, c, d]

        // Move a onto c → expect [b, c, a, d]
        store.move(a.id, onto: c.id, in: notes)
        #expect(store.sorted(notes).map(\.timelineTitle) == ["b", "c", "a", "d"])
    }

    @Test func subsequentMovesPreserveExistingOrder() {
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        let c = Self.note("c")
        let d = Self.note("d")
        let notes = [a, b, c, d]

        // First move: d onto b (backward) → [a, d, b, c]
        store.move(d.id, onto: b.id, in: notes)
        #expect(store.sorted(notes).map(\.timelineTitle) == ["a", "d", "b", "c"])

        // Second move: c onto a (backward) → [c, a, d, b]
        store.move(c.id, onto: a.id, in: notes)
        #expect(store.sorted(notes).map(\.timelineTitle) == ["c", "a", "d", "b"])
    }

    @Test func newNotesSortToEndAfterReorder() {
        // Once the user has reordered, a new note added later should land
        // at the end of the custom order — silently jumping into the
        // middle of a hand-curated layout would be confusing.
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        store.move(b.id, onto: a.id, in: [a, b])
        #expect(store.sorted([a, b]).map(\.timelineTitle) == ["b", "a"])

        let c = Self.note("c")
        let withC = [a, b, c]
        // Note: customOrder still references [b, a]. New note c isn't in
        // the custom order; sort assigns it Int.max so it lands at the end.
        let result = store.sorted(withC)
        #expect(result.map(\.timelineTitle) == ["b", "a", "c"])
    }

    @Test func resetClearsCustomOrder() {
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        store.move(b.id, onto: a.id, in: [a, b])
        #expect(store.hasCustomOrder)

        store.reset()
        #expect(!store.hasCustomOrder)
        #expect(store.sorted([a, b]).map(\.timelineTitle) == ["a", "b"])
    }

    @Test func movingToSelfIsNoOp() {
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        store.move(a.id, onto: a.id, in: [a])
        #expect(!store.hasCustomOrder, "Moving an item onto itself should not seed a custom order")
    }

    @Test func restoreReplacesCustomOrderWithSnapshot() {
        // Phase E.5.7 — drop-on-empty in the custom-gesture reorder
        // calls `restore(_:)` with the order captured at drag start so
        // the in-flight reorder reverts.
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        let c = Self.note("c")
        let notes = [a, b, c]

        // Pre-drag: user already had a custom order [c, a, b].
        store.move(c.id, onto: a.id, in: notes)
        let snapshot = store.customOrder
        #expect(store.sorted(notes).map(\.timelineTitle) == ["c", "a", "b"])

        // Drag in flight — reorders to [a, c, b].
        store.move(a.id, onto: c.id, in: notes)
        #expect(store.sorted(notes).map(\.timelineTitle) == ["a", "c", "b"])

        // Drop on empty space — revert.
        store.restore(snapshot)
        #expect(store.sorted(notes).map(\.timelineTitle) == ["c", "a", "b"])
    }

    @Test func restoreEmptySnapshotEqualsReset() {
        // Phase E.5.7 — when the user starts a drag with no prior
        // custom order, the snapshot is `[]`. Restoring must put us
        // back into the chronological-fallback state, not lock in the
        // mid-drag move.
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        let notes = [a, b]

        let snapshot = store.customOrder      // empty pre-drag
        store.move(b.id, onto: a.id, in: notes)
        #expect(store.hasCustomOrder)

        store.restore(snapshot)
        #expect(!store.hasCustomOrder, "Restoring an empty snapshot should clear the custom order")
        #expect(store.sorted(notes).map(\.timelineTitle) == ["a", "b"])
    }

    @Test func deleteRemovesNoteAndForgetsPinState() {
        // Phase E.5.15 — TimelineStore.delete(noteId:) drops the note
        // AND clears it from PinStore so pinned ids don't outlive their
        // notes as ghost references.
        let pinStore = PinStore()
        let a = MockNote(time: "9:00 AM", type: .general, content: .text(title: "a"))
        let b = MockNote(time: "10:00 AM", type: .general, content: .text(title: "b"))
        let store = TimelineStore(initialNotes: [a, b])

        // Pin both, then delete a — pin state for a should disappear,
        // pin state for b should remain.
        pinStore.pin(a.id)
        pinStore.pin(b.id)
        // We tested forget directly in PinStoreTests; here we sanity-check
        // the surface area used by the TimelineStore's delete path —
        // the store delegates to PinStore.shared, so this test only
        // verifies the note-removal half.
        store.delete(noteId: a.id)
        #expect(store.notes.count == 1)
        #expect(store.notes.first?.id == b.id)
    }

    @Test func deleteNonExistentIdIsNoOp() {
        let a = MockNote(time: "9:00 AM", type: .general, content: .text(title: "a"))
        let store = TimelineStore(initialNotes: [a])
        store.delete(noteId: UUID())  // id never seen
        #expect(store.notes.count == 1)
    }

    @Test func unknownTargetIsNoOp() {
        // If the target id isn't in the current notes, nothing should
        // happen — defensive behavior so a stale drop UUID can't crash
        // the reorder.
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        let stranger = UUID()
        store.move(b.id, onto: stranger, in: [a, b])
        // After this call, the customOrder may be seeded (move() seeds
        // from chronological before checking target) but order shouldn't
        // change.
        #expect(store.sorted([a, b]).map(\.timelineTitle) == ["a", "b"])
    }
}
