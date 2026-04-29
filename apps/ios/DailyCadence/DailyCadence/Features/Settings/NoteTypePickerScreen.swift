import SwiftUI

/// Settings → Appearance → Note Types.
///
/// Lists every `NoteType` (General, the five categories, Media) with
/// their current color. Tapping a row pushes a swatch picker that lets
/// the user override that type's color. Selections persist via
/// `NoteTypeStyleStore` and propagate everywhere `NoteType.color` is
/// read (timeline dots, KeepCard borders, TypeChip icons, type badges).
///
/// The data legend stays intact: each type still has ONE color across the
/// app — it's just the user's choice instead of the design-system default.
struct NoteTypePickerScreen: View {
    var body: some View {
        List {
            Section {
                ForEach(NoteType.allCases) { type in
                    NavigationLink {
                        TextColorPickerScreen(
                            selectedColorId: bindingForOverride(of: type),
                            title: "\(type.title) color"
                        )
                    } label: {
                        row(for: type)
                    }
                    .listRowBackground(Color.DS.bg2)
                }
            } footer: {
                Text("Pick a color for each note type. The change applies everywhere that type appears: timeline dots, card borders, icons. Note backgrounds and text colors stay separate.")
                    .font(.DS.small)
                    .foregroundStyle(Color.DS.fg2)
            }

            Section {
                Button(role: .destructive) {
                    NoteTypeStyleStore.shared.resetAll()
                } label: {
                    HStack {
                        Text("Reset all to default")
                        Spacer()
                    }
                }
                .listRowBackground(Color.DS.bg2)
                .disabled(NoteTypeStyleStore.shared.overrides.isEmpty)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.DS.bg1)
        .navigationTitle("Note Types")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for type: NoteType) -> some View {
        let store = NoteTypeStyleStore.shared
        let override = store.swatch(for: type)
        return HStack(spacing: 12) {
            // Colored circle showing the type's CURRENT color (override or default)
            Circle()
                .fill(type.color)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.DS.border1, lineWidth: 1))
            Image(systemName: type.systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.DS.fg2)
                .frame(width: 18)
            Text(type.title)
                .foregroundStyle(Color.DS.ink)
            Spacer(minLength: 8)
            Text(override?.name ?? "Default")
                .foregroundStyle(Color.DS.fg2)
        }
    }

    /// Two-way binding into `NoteTypeStyleStore` for one type. Reading
    /// returns the stored swatch id (or `nil` for default); writing calls
    /// `setSwatchId(_:for:)`.
    private func bindingForOverride(of type: NoteType) -> Binding<String?> {
        Binding(
            get: { NoteTypeStyleStore.shared.overrides[type.rawValue] },
            set: { newId in NoteTypeStyleStore.shared.setSwatchId(newId, for: type) }
        )
    }
}

#Preview("Light") {
    NavigationStack { NoteTypePickerScreen() }
}

#Preview("Dark") {
    NavigationStack { NoteTypePickerScreen() }
        .preferredColorScheme(.dark)
}
