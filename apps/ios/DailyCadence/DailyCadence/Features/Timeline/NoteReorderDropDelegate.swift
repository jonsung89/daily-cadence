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

    /// Live reflow during drag.
    func dropEntered(info: DropInfo) {
        guard let draggingId = DragSessionStore.shared.draggingNoteId,
              draggingId != targetNote.id else { return }
        Self.move(droppedId: draggingId, before: targetNote.id, in: allNotes)
    }

    /// Drop release — clears the session, and as a fallback re-applies
    /// the move in case `dropEntered` was missed for the target card
    /// (e.g., the drop landed without a final hover event).
    func performDrop(info: DropInfo) -> Bool {
        if let draggingId = DragSessionStore.shared.draggingNoteId,
           draggingId != targetNote.id {
            Self.move(droppedId: draggingId, before: targetNote.id, in: allNotes)
        }
        DragSessionStore.shared.draggingNoteId = nil
        return true
    }

    private static func move(droppedId: UUID, before targetId: UUID, in notes: [MockNote]) {
        guard droppedId != targetId else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            CardsViewOrderStore.shared.move(droppedId, before: targetId, in: notes)
        }
    }
}
