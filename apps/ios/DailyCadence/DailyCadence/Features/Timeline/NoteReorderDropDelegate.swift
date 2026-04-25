import SwiftUI
import UniformTypeIdentifiers

/// Drop delegate for the Cards Board layout's drag-to-reorder.
///
/// Pairs with `DragSessionStore.shared.draggingNoteId`, which the
/// `.draggable { ... }` closure on each `KeepCard` populates **at drag
/// start**. That makes the dragging id available synchronously here —
/// `dropEntered` doesn't have to await `NSItemProvider.loadObject(...)`,
/// which iOS often defers until drop time and which would otherwise
/// prevent live reflow during the drag.
///
/// **What this delegate does:**
/// - `dropUpdated` returns `DropProposal(operation: .move)` so iOS uses
///   the move indicator instead of the green "+" copy badge.
/// - `dropEntered` triggers the actual reorder the moment the drag enters
///   this card's hit zone — that's what makes the surrounding cards
///   shift live under the floating drag preview.
/// - `performDrop` is a fallback: if `dropEntered` didn't fire (rare
///   edge cases — quick drops, screen edges), it commits the reorder on
///   drop release.
struct NoteReorderDropDelegate: DropDelegate {
    let targetNote: MockNote
    let allNotes: [MockNote]

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    /// Live reflow during drag. Also publishes this card as the current
    /// drop target so it can render a "live drop" outline.
    func dropEntered(info: DropInfo) {
        DragSessionStore.shared.currentDropTargetId = targetNote.id
        guard let draggingId = DragSessionStore.shared.draggingNoteId,
              draggingId != targetNote.id else { return }
        // Cascade guard: as cards animate during live reflow, the user's
        // stationary finger crosses between drop zones and triggers
        // multiple `dropEntered`s in quick succession. Skip if we've
        // already moved relative to this exact target — re-firing the
        // move would just bounce the card around.
        if DragSessionStore.shared.lastMoveTargetId == targetNote.id { return }
        DragSessionStore.shared.lastMoveTargetId = targetNote.id
        Self.move(droppedId: draggingId, before: targetNote.id, in: allNotes)
    }

    /// Hover ended — clear the highlight if we were the active target.
    /// Don't touch `draggingNoteId`; the drag is still active and
    /// likely about to enter another card's zone.
    func dropExited(info: DropInfo) {
        if DragSessionStore.shared.currentDropTargetId == targetNote.id {
            DragSessionStore.shared.currentDropTargetId = nil
        }
    }

    /// Drop release — clears the session, and as a fallback re-applies
    /// the move in case `dropEntered` was missed for the target card
    /// (e.g., the drop landed without a final hover event).
    func performDrop(info: DropInfo) -> Bool {
        if let draggingId = DragSessionStore.shared.draggingNoteId,
           draggingId != targetNote.id {
            Self.move(droppedId: draggingId, before: targetNote.id, in: allNotes)
        }
        DragSessionStore.shared.endSession()
        return true
    }

    private static func move(droppedId: UUID, before targetId: UUID, in notes: [MockNote]) {
        guard droppedId != targetId else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            CardsViewOrderStore.shared.move(droppedId, before: targetId, in: notes)
        }
    }
}
