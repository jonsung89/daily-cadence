import Foundation
import Observation

/// Tracks which notes the user has pinned (Phase E.5.15).
///
/// **Why a separate store.** Pinning is a per-note attribute (model state),
/// not a per-view setting (view state). Keeping it in its own
/// `@Observable` singleton — separate from `TimelineStore` (which owns the
/// note collection) and `CardsViewOrderStore` (which owns the Board's
/// custom ordering) — makes the eventual migration to Supabase a single
/// boolean column with one store responsible for it. It also avoids
/// mutating `MockNote`, which is intentionally immutable (`let` fields,
/// snapshot-style).
///
/// **Lifecycle.**
/// - `togglePin(_:UUID)` flips a note's pin state.
/// - `isPinned(_:UUID)` is the read-through used by every card + every
///   view that splits notes by pin state.
/// - In-memory only for Phase 1 (matches the rest of the persistence
///   model). Supabase / UserDefaults persistence is a Phase F follow-up.
///
/// **Read pattern.** Views read through `PinStore.shared.isPinned(note.id)`
/// inside `body`, so the Observation framework registers them as
/// observers and re-renders when pin state changes — same pattern as
/// `ThemeStore.shared.primary` etc.
@Observable
final class PinStore {
    static let shared = PinStore()

    /// The set of pinned note ids. Stored as `Set` for O(1) lookup; the
    /// pinned-section render path iterates a notes array externally and
    /// asks "is this id pinned?" rather than the reverse.
    private(set) var pinnedIds: Set<UUID> = []

    init(initialPinnedIds: Set<UUID> = []) {
        self.pinnedIds = initialPinnedIds
    }

    /// True when `noteId` is currently pinned.
    func isPinned(_ noteId: UUID) -> Bool {
        pinnedIds.contains(noteId)
    }

    /// Flips the pin state for `noteId`. Returns the new state so callers
    /// can branch (e.g., to fire a haptic, log analytics).
    @discardableResult
    func togglePin(_ noteId: UUID) -> Bool {
        if pinnedIds.contains(noteId) {
            pinnedIds.remove(noteId)
            return false
        } else {
            pinnedIds.insert(noteId)
            return true
        }
    }

    /// Explicit pin (idempotent — safe to call on an already-pinned id).
    func pin(_ noteId: UUID) {
        pinnedIds.insert(noteId)
    }

    /// Explicit unpin (idempotent — safe to call on an already-unpinned id).
    func unpin(_ noteId: UUID) {
        pinnedIds.remove(noteId)
    }

    /// Removes `noteId` from the pinned set if it was there. Called by
    /// `TimelineStore.delete(_:)` so a deleted note doesn't leave its id
    /// lingering as a "ghost pin."
    func forget(_ noteId: UUID) {
        pinnedIds.remove(noteId)
    }
}
