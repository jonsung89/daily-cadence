import SwiftUI

/// Phase F.1.2.caption — lightweight sheet for editing the caption of an
/// existing media note. Reuses neither `MediaNoteEditorScreen` (which
/// owns the full create/edit flow including media replace + crop +
/// occurredAt picker) nor `NoteEditorScreen` (text-note editor) — the
/// only thing that's editable here is the caption string. Keeping the
/// surface focused matches the long-press-menu entry point: the user
/// asked to edit *the caption*, not the whole note.
///
/// Presents as a `.medium` detent sheet with a multi-line TextField and
/// Cancel / Save toolbar. On save, hands the new caption back via the
/// `onSave` closure; the caller reconstructs the `MockNote` with the
/// updated `MediaPayload` and forwards to `TimelineStore.update`. On
/// cancel, dismisses without persisting.
struct CaptionEditSheet: View {
    /// Initial caption — pre-fills the TextField. `nil` is treated as
    /// empty so the placeholder shows.
    let initialCaption: String?
    /// Fires once on Save with the trimmed caption (or `nil` if the
    /// user cleared it). Caller is responsible for the round-trip
    /// through `TimelineStore.update`.
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftCaption: String

    init(initialCaption: String?, onSave: @escaping (String?) -> Void) {
        self.initialCaption = initialCaption
        self.onSave = onSave
        self._draftCaption = State(initialValue: initialCaption ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                if draftCaption.isEmpty {
                    Text("Add a caption…")
                        .font(.DS.sans(size: 16, weight: .regular))
                        .foregroundStyle(Color.DS.ink.opacity(0.4))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextField(
                    "Caption",
                    text: $draftCaption,
                    axis: .vertical
                )
                .font(.DS.sans(size: 16, weight: .regular))
                .foregroundStyle(Color.DS.ink)
                .lineLimit(3...10)
                .textFieldStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.DS.bg1)
            .navigationTitle("Edit caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = draftCaption.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                    // No disabled state — saving an empty caption is
                    // valid (clears it). User can also Cancel for "no
                    // change."
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview("With caption") {
    Text("Long press a card")
        .sheet(isPresented: .constant(true)) {
            CaptionEditSheet(
                initialCaption: "Sunset at the lake — peaceful day",
                onSave: { _ in }
            )
        }
}

#Preview("Empty") {
    Text("Long press a card")
        .sheet(isPresented: .constant(true)) {
            CaptionEditSheet(initialCaption: nil, onSave: { _ in })
        }
}
