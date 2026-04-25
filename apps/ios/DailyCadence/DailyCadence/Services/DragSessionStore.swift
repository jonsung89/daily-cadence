import Foundation
import SwiftUI

/// Tracks which note is currently being dragged for the Free Board's
/// live-reflow reorder (Phase E.4.8).
///
/// **Why this exists.** The reorder reads the dragged note's UUID from a
/// `NSItemProvider` payload (set up by `.draggable(_:)`). That call is
/// asynchronous, so the *first* `dropEntered` event for a given drag has
/// to load the payload, but subsequent events (as the drag passes over
/// other cards) need to react synchronously — otherwise the live reflow
/// stutters waiting for the same UUID to keep loading. Caching the
/// dragging id here closes that loop.
///
/// **Lifecycle.**
/// - First `dropEntered` per drag → async load + set `draggingNoteId`.
/// - Subsequent `dropEntered` events → read `draggingNoteId` synchronously
///   and trigger the reorder animation.
/// - `performDrop` → clear `draggingNoteId` so the next drag starts clean.
///
/// In-memory only and intentionally not exposed beyond the reorder
/// machinery; if other features ever need drag state we can promote it.
@Observable
final class DragSessionStore {
    static let shared = DragSessionStore()

    var draggingNoteId: UUID? = nil

    init() {}
}
