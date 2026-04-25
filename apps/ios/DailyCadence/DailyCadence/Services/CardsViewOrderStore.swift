import Foundation
import SwiftUI

/// Custom note ordering for the Board's **Cards** layout (Phase E.4.3,
/// renamed from `FreeViewOrderStore` in Phase E.5.1 alongside the
/// "Free → Cards" layout-mode rename).
///
/// **What this is.** The Board's Stack and Group layouts organize notes by
/// `NoteType`, so their order is implicit. The **Cards** layout is
/// chronological by default but lets the user shuffle cards via
/// drag-and-drop — same affordance as Google Keep's reorder. This store
/// holds the per-user shuffle as an ordered list of note ids.
///
/// **Lifecycle.**
/// - Empty `customOrder` ⇒ Cards view falls back to the timeline's
///   chronological order from `TimelineStore`.
/// - User drags a card on top of another ⇒ `move(_:before:in:)` initializes
///   `customOrder` from the current chronological list (so subsequent
///   sorts are stable) and inserts the dragged note at the new position.
/// - User taps **Reset order** ⇒ `reset()` empties `customOrder` and the
///   Cards view falls back to chronological.
///
/// **Forward-compatibility.** New notes added via the FAB after the user
/// has reordered are appended to the end of the custom order so they
/// don't silently jump into the middle of a hand-curated layout. If a note
/// is deleted, its id stays in `customOrder` as an inert leftover; cleanup
/// can come later if it ever matters.
///
/// **Scope.** In-memory only — drift across app relaunches is acceptable
/// for Phase 1. UserDefaults / Supabase persistence is a Phase F follow-up.
@Observable
final class CardsViewOrderStore {
    static let shared = CardsViewOrderStore()

    private(set) var customOrder: [UUID] = []

    /// `true` when the user has shuffled at least once. Drives the Reset
    /// pill's visibility.
    var hasCustomOrder: Bool { !customOrder.isEmpty }

    init() {}

    /// Returns `notes` sorted by the custom order. Notes not yet seen
    /// (added after the last reorder) sort to the end, preserving their
    /// chronological position relative to each other.
    func sorted(_ notes: [MockNote]) -> [MockNote] {
        guard !customOrder.isEmpty else { return notes }
        let positionMap = Dictionary(
            uniqueKeysWithValues: customOrder.enumerated().map { ($1, $0) }
        )
        // Sort with a stable key — known notes use their custom position,
        // unknown notes go to the end (Int.max), and ties preserve the
        // input array's order via Swift's stable `sort`.
        return notes.enumerated().sorted { lhs, rhs in
            let lhsPos = positionMap[lhs.element.id] ?? Int.max
            let rhsPos = positionMap[rhs.element.id] ?? Int.max
            if lhsPos != rhsPos { return lhsPos < rhsPos }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Moves `draggedId` to immediately before `targetId` in the custom
    /// order. If this is the first reorder, `customOrder` is initialized
    /// from `notes`'s current chronological order so the move has a
    /// stable reference frame.
    func move(_ draggedId: UUID, before targetId: UUID, in notes: [MockNote]) {
        guard draggedId != targetId else { return }

        // Seed from the chronological order on first move; otherwise,
        // start from the existing custom order.
        var order = customOrder.isEmpty ? notes.map(\.id) : customOrder

        // Append any notes that have appeared since the last reorder so
        // they have a deterministic slot before we move things around.
        let existing = Set(order)
        for note in notes where !existing.contains(note.id) {
            order.append(note.id)
        }

        order.removeAll(where: { $0 == draggedId })
        guard let targetIdx = order.firstIndex(of: targetId) else { return }
        order.insert(draggedId, at: targetIdx)
        customOrder = order
    }

    /// Restores chronological order. UI that reads `hasCustomOrder` should
    /// hide its reset affordance after this returns.
    func reset() {
        customOrder = []
    }
}
