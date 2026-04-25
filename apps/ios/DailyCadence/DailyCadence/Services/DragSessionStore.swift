import Foundation
import SwiftUI

/// Tracks the active drag-to-reorder session for the Cards Board layout
/// (Phase E.4.8 → E.5.5).
///
/// Two pieces of state, both `@Observable` so views that read them inside
/// `body` re-render automatically:
///
/// - **`draggingNoteId`** — the source card the user is currently
///   dragging. Set by `.onDrag`'s closure at drag start; read by
///   `NoteReorderDropDelegate` so its `dropEntered` can react
///   synchronously without awaiting an async `NSItemProvider.loadObject`.
///   Source cards read this to fade out while they're the drag source
///   (visual confirmation the drag started).
///
/// - **`currentDropTargetId`** — the card the finger is currently
///   hovering over. Maintained by the drop delegate's `dropEntered` /
///   `dropExited` pair. Cards read this to render a subtle highlight on
///   themselves when they're the live drop target — gives the user a
///   clear "this is where it'll land" cue during the drag.
///
/// **Lifecycle.**
/// - **Drag start** → `.onDrag` sets `draggingNoteId`.
/// - **Hover over card** → `dropEntered` sets `currentDropTargetId`,
///   moves the dragged note before that target.
/// - **Hover off card** → `dropExited` clears `currentDropTargetId` (but
///   leaves `draggingNoteId` intact — drag is still active).
/// - **Release** → `performDrop` clears both.
/// - **Cancel** (drag dropped outside any target) → no callback fires,
///   so state would linger. The next drag's `.onDrag` overwrites
///   `draggingNoteId`, which is the cleanup signal we lean on.
///
/// In-memory only — drift across app launches is irrelevant since drags
/// don't outlive a session.
@Observable
final class DragSessionStore {
    static let shared = DragSessionStore()

    var draggingNoteId: UUID? = nil
    var currentDropTargetId: UUID? = nil
    /// The most recent target id we've already committed a `move(_:before:)`
    /// for during this drag session. Guards against the **dropEntered
    /// cascade**: as cards animate to new positions during live reflow,
    /// the user's stationary finger ends up over different cards, each
    /// firing `dropEntered` again. Without this guard the move would
    /// recompute several times per hover and the dragged card could
    /// "bounce" through positions before the user releases.
    var lastMoveTargetId: UUID? = nil

    init() {}

    /// Clears every drag-related id. Called from `performDrop` and
    /// `.onDrag`'s drag-start hook (so a previous session that ended
    /// without a `performDrop` — e.g. the user dropped on the source
    /// itself, which iOS filters as a drop target — gets cleaned up at
    /// the start of the next drag).
    func endSession() {
        draggingNoteId = nil
        currentDropTargetId = nil
        lastMoveTargetId = nil
    }
}
