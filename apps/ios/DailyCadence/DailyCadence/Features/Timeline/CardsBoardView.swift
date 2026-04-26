import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drag payload

/// Intra-app drag payload for Cards-board reorder.
///
/// Wrapping the note id in a typed `Transferable` (rather than passing
/// `String` or raw `UUID`) keeps the drag confined to our own
/// `.dropDestination(for: NoteDragPayload.self)` targets — text-accepting
/// apps like Notes or Mail don't advertise as drop sites because the
/// content type is generic `.data`.
struct NoteDragPayload: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - Cards board view

/// Pure-SwiftUI Cards layout for the Board screen.
///
/// **Reorder uses `.draggable` + `.dropDestination`.** Both route through
/// iOS's system drag-and-drop (`UIDragInteraction` under the hood),
/// which arbitrates with the parent `ScrollView`'s pan recognizer at
/// the UIKit gesture layer — the page continues to scroll from any
/// touch start, including over a card. The system handles the long-press
/// initiation, haptic, lift, floating preview, and cancel-on-empty-space
/// for free.
///
/// `KeepCard`'s built-in `.contextMenu` (Pin / Delete) coexists naturally:
/// tap-and-hold-without-drift triggers the menu; tap-and-hold-then-drag
/// initiates the reorder. Standard iOS disambiguation, no manual gesture
/// coordination.
struct CardsBoardView: View {
    let notes: [MockNote]
    let onRequestDelete: (UUID) -> Void

    var body: some View {
        MasonryLayout(columns: 2, spacing: 12) {
            ForEach(notes) { note in
                KeepCard(
                    note: note,
                    onRequestDelete: { onRequestDelete($0.id) }
                )
                .draggable(NoteDragPayload(id: note.id))
                .dropDestination(for: NoteDragPayload.self) { payloads, _ in
                    guard let sourceID = payloads.first?.id,
                          sourceID != note.id else { return false }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        CardsViewOrderStore.shared.move(
                            sourceID,
                            onto: note.id,
                            in: notes
                        )
                    }
                    return true
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Cards board, light") {
    ScrollView {
        CardsBoardView(
            notes: MockNotes.today,
            onRequestDelete: { _ in }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    .background(Color.DS.bg1)
}

#Preview("Cards board, dark") {
    ScrollView {
        CardsBoardView(
            notes: MockNotes.today,
            onRequestDelete: { _ in }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}
