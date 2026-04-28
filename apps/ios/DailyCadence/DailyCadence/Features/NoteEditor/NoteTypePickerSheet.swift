import SwiftUI

/// Phase F.1.2.picker — Apple-Settings-style searchable picker for the
/// note type. Replaces the editor's previous horizontal-scroll chip row
/// which became a hunt at 7+ types and didn't scale to custom user
/// types (Phase F+).
///
/// **Combo A+B** (per the captured TODO discussion):
/// - **A. Defer the decision.** The editor opens straight to writing;
///   the type is represented by a single chip near the title. The user
///   never has to interact with a type picker just to start typing.
/// - **B. Searchable sheet.** Tap the chip → this sheet presents.
///   Search field at the top + a wrapping flow of all types (chips
///   sized to their natural width, evenly spread per row). Type to
///   filter live, tap any type to commit + dismiss. Scales to N
///   types without changing the UI.
///
/// Returns the chosen type via `onSelect`. Cancel via the toolbar
/// dismisses without changing the selection.
struct NoteTypePickerSheet: View {
    /// Currently-selected type — drives the highlighted cell so the
    /// user can see which one they're on without re-deriving it.
    let selectedType: NoteType
    /// Fires once when the user taps a grid cell. Caller is responsible
    /// for committing into the draft / form state.
    let onSelect: (NoteType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                FlowLayout(spacing: 12, rowSpacing: 12, alignment: .center) {
                    ForEach(filteredTypes) { type in
                        TypeChip(
                            type: type,
                            isSelected: type == selectedType,
                            action: {
                                onSelect(type)
                                dismiss()
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)

                if filteredTypes.isEmpty {
                    Text("No types match \u{201C}\(query)\u{201D}")
                        .font(.DS.sans(size: 14, weight: .regular))
                        .foregroundStyle(Color.DS.fg2)
                        .padding(.top, 32)
                }
            }
            .background(Color.DS.bg1)
            .navigationTitle("Note type")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search types"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// User-pickable types matched against the live query. `.media` is
    /// excluded — bare media notes are auto-tagged on save by
    /// `MediaNoteEditorScreen` (Phase E.5.10) and shouldn't be a manual
    /// pick from the text-note editor.
    private var filteredTypes: [NoteType] {
        let pickable = NoteType.textEditorPickable
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return pickable }
        return pickable.filter { $0.title.lowercased().contains(q) }
    }
}

#Preview {
    Text("Tap a chip in the editor")
        .sheet(isPresented: .constant(true)) {
            NoteTypePickerSheet(
                selectedType: .general,
                onSelect: { _ in }
            )
        }
}
