import Foundation
import Testing
@testable import DailyCadence

/// Phase E.5.15 — verifies `PinStore`'s pin / unpin / toggle / forget
/// semantics so Pinned-section rendering stays honest.
struct PinStoreTests {

    @Test func defaultStateHasNoPins() {
        let store = PinStore()
        #expect(store.pinnedIds.isEmpty)
        #expect(store.isPinned(UUID()) == false)
    }

    @Test func togglePinFlipsState() {
        let store = PinStore()
        let id = UUID()
        let firstResult = store.togglePin(id)
        #expect(firstResult == true)
        #expect(store.isPinned(id))

        let secondResult = store.togglePin(id)
        #expect(secondResult == false)
        #expect(store.isPinned(id) == false)
    }

    @Test func explicitPinIsIdempotent() {
        let store = PinStore()
        let id = UUID()
        store.pin(id)
        store.pin(id)
        #expect(store.pinnedIds.count == 1)
        #expect(store.isPinned(id))
    }

    @Test func explicitUnpinIsIdempotentForUnknownIds() {
        let store = PinStore()
        let id = UUID()
        store.unpin(id)  // no-op when id wasn't pinned
        #expect(store.pinnedIds.isEmpty)
    }

    @Test func forgetRemovesIdFromPinnedSet() {
        // `TimelineStore.delete(noteId:)` calls `forget(_:)` so a deleted
        // note doesn't leave a "ghost pin" referencing a dead id.
        let store = PinStore()
        let id = UUID()
        store.pin(id)
        store.forget(id)
        #expect(store.isPinned(id) == false)
        #expect(store.pinnedIds.isEmpty)
    }

    @Test func multiplePinsCoexist() {
        let store = PinStore()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        store.pin(a)
        store.pin(b)
        store.pin(c)
        #expect(store.pinnedIds == [a, b, c])
        store.unpin(b)
        #expect(store.pinnedIds == [a, c])
    }
}
