import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drag payload

/// Intra-app drag payload for Cards-board reorder.
///
/// `.draggable(NoteDragPayload(...))` produces an `NSItemProvider`
/// advertising the generic `.data` content type. The drop delegate
/// matches on `.data` and decodes the JSON-encoded payload back. Text-
/// accepting apps like Notes / Mail don't advertise as drop sites for
/// `.data`, so the drag stays intra-app without registering a custom
/// UTType in Info.plist.
struct NoteDragPayload: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - Drop delegate

/// Reorder drop delegate. Returns `DropProposal(operation: .move)` from
/// `dropUpdated` so the system shows iOS's "move" cursor instead of the
/// green `+` "copy" badge — the drag is an in-place reorder, not an add.
///
/// The modern `.dropDestination(for:action:)` modifier doesn't expose
/// the drop operation, so it always defaults to `.copy` and surfaces the
/// `+` badge. Falling back to the legacy `.onDrop(of:delegate:)` API is
/// the only way to specify `.move` in SwiftUI. Same approach Apple uses
/// in their own reorder flows.
struct CardsReorderDropDelegate: DropDelegate {
    let targetID: UUID
    let notes: [MockNote]

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.data])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.data]).first else {
            return false
        }
        let target = targetID
        let snapshot = notes
        provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
            guard let data,
                  let payload = try? JSONDecoder().decode(NoteDragPayload.self, from: data),
                  payload.id != target else { return }
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.22)) {
                    CardsViewOrderStore.shared.move(payload.id, onto: target, in: snapshot)
                }
            }
        }
        return true
    }
}

// MARK: - Cards board view

/// Pure-SwiftUI Cards layout for the Board screen.
///
/// **Reorder.** Drag side uses SwiftUI's `.draggable` (system drag, gets
/// haptic + lift + floating preview + scroll arbitration for free). Drop
/// side uses the legacy `.onDrop(of:delegate:)` + a `DropDelegate` whose
/// `dropUpdated` returns `.move` — that's how we suppress the system's
/// default green `+` "copy" badge on the drag preview, since the modern
/// `.dropDestination` modifier doesn't expose operation type.
///
/// `KeepCard`'s built-in `.contextMenu` (Pin / Delete) coexists naturally:
/// tap-and-hold-without-drift triggers the menu; tap-and-hold-then-drag
/// initiates the reorder. Standard iOS disambiguation, no manual gesture
/// coordination.
struct CardsBoardView: View {
    let notes: [MockNote]
    let onRequestDelete: (UUID) -> Void
    /// Phase F.1.0 — forwarded to each text card's `onTap` callback so
    /// tapping opens the editor. Optional so previews don't have to wire it.
    var onRequestEdit: ((UUID) -> Void)? = nil
    /// Phase F.1.1b'.zoom — forwarded to each card so media taps route
    /// through the parent's namespace + navigation push. Optional so
    /// previews work without it (cards fall back to `.fullScreenCover`).
    var mediaTapHandler: MediaTapHandler? = nil
    /// Phase F.1.2.caption — forwarded to media cards' long-press menu.
    var onRequestEditCaption: ((UUID) -> Void)? = nil

    var body: some View {
        MasonryLayout(columns: 2, spacing: 12) {
            ForEach(notes) { note in
                KeepCard(
                    note: note,
                    onRequestDelete: { onRequestDelete($0.id) },
                    onTap: onRequestEdit.map { cb in { cb(note.id) } },
                    mediaTapHandler: mediaTapHandler,
                    onRequestEditCaption: onRequestEditCaption.map { cb in { cb($0.id) } }
                )
                .draggable(NoteDragPayload(id: note.id))
                .onDrop(
                    of: [.data],
                    delegate: CardsReorderDropDelegate(targetID: note.id, notes: notes)
                )
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
