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

    @Test func moveSeedsFromChronologicalAndInsertsBeforeTarget() {
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        let c = Self.note("c")
        let notes = [a, b, c]

        // Move c before a → expect [c, a, b]
        store.move(c.id, before: a.id, in: notes)
        #expect(store.hasCustomOrder)
        #expect(store.sorted(notes).map(\.timelineTitle) == ["c", "a", "b"])
    }

    @Test func subsequentMovesPreserveExistingOrder() {
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        let c = Self.note("c")
        let d = Self.note("d")
        let notes = [a, b, c, d]

        // First move: d before b → [a, d, b, c]
        store.move(d.id, before: b.id, in: notes)
        #expect(store.sorted(notes).map(\.timelineTitle) == ["a", "d", "b", "c"])

        // Second move: c before a → [c, a, d, b]
        store.move(c.id, before: a.id, in: notes)
        #expect(store.sorted(notes).map(\.timelineTitle) == ["c", "a", "d", "b"])
    }

    @Test func newNotesSortToEndAfterReorder() {
        // Once the user has reordered, a new note added later should land
        // at the end of the custom order — silently jumping into the
        // middle of a hand-curated layout would be confusing.
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        store.move(b.id, before: a.id, in: [a, b])
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
        store.move(b.id, before: a.id, in: [a, b])
        #expect(store.hasCustomOrder)

        store.reset()
        #expect(!store.hasCustomOrder)
        #expect(store.sorted([a, b]).map(\.timelineTitle) == ["a", "b"])
    }

    @Test func movingToSelfIsNoOp() {
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        store.move(a.id, before: a.id, in: [a])
        #expect(!store.hasCustomOrder, "Moving an item before itself should not seed a custom order")
    }

    @Test func unknownTargetIsNoOp() {
        // If the target id isn't in the current notes, nothing should
        // happen — defensive behavior so a stale drop UUID can't crash
        // the reorder.
        let store = CardsViewOrderStore()
        let a = Self.note("a")
        let b = Self.note("b")
        let stranger = UUID()
        store.move(b.id, before: stranger, in: [a, b])
        // After this call, the customOrder may be seeded (move() seeds
        // from chronological before checking target) but order shouldn't
        // change.
        #expect(store.sorted([a, b]).map(\.timelineTitle) == ["a", "b"])
    }
}
