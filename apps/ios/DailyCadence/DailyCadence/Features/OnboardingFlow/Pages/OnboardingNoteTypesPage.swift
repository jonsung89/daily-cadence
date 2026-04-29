import SwiftUI

/// Note types page — gives the user an early peek at the type
/// vocabulary and a chance to recolor any of them. Reuses the
/// `TextColorPickerScreen` from Settings (presented as a sheet) so
/// the picker UI is exactly what they'll see later.
///
/// Custom-type creation is deferred to a follow-up round (the
/// `+ Add custom type` button surfaces a placeholder alert). Schema
/// supports it via `note_types.created_by_user_id`; the missing piece
/// is the INSERT UI + per-type structured-data schema picker, which
/// warrants its own session.
struct OnboardingNoteTypesPage: View {
    let pageIndex: Int
    let pageCount: Int
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var editingType: NoteType?
    @State private var customAlertVisible = false

    var body: some View {
        // Touch the override store so the row chips re-render when
        // the user picks a new color in the sheet.
        let _ = NoteTypeStyleStore.shared.overrides

        return OnboardingChrome(
            pageIndex: pageIndex,
            pageCount: pageCount,
            title: "Your note types",
            body: "Color-code the kinds of things you log. Tap any type to change its color.",
            primaryLabel: "Continue",
            onPrimary: onContinue,
            onSkip: onSkip
        ) {
            heroStack
        } control: {
            controlStack
        }
        .sheet(item: $editingType) { type in
            NavigationStack {
                TextColorPickerScreen(
                    selectedColorId: typeColorBinding(for: type),
                    title: type.title
                )
            }
        }
        .alert("Custom types coming soon", isPresented: $customAlertVisible) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You'll be able to create your own note types in a future update. For now you can recolor any of the existing ones.")
        }
    }

    private var heroStack: some View {
        // Mirrors the icon shape used in the type rows below — same
        // 25% corner radius, same continuous squircle, same color +
        // SF Symbol glyph. Three of them stacked at offsets and a
        // slight rotation so it reads as a fanned deck and previews
        // exactly what the list will look like.
        ZStack {
            ForEach(Array(NoteType.allCases.prefix(3).enumerated()), id: \.element) { index, type in
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(type.color)
                    Image(systemName: type.systemImage)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.DS.fgOnAccent)
                }
                .frame(width: 64, height: 64)
                .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
                .offset(
                    x: CGFloat(index - 1) * 36,
                    y: CGFloat(index - 1) * 6
                )
                .rotationEffect(.degrees(Double(index - 1) * -6))
                .zIndex(Double(-abs(index - 1)))
            }
        }
        .padding(.top, Spacing.s4)
    }

    private var controlStack: some View {
        VStack(spacing: 10) {
            ForEach(NoteType.allCases) { type in
                Button { editingType = type } label: { typeRow(type) }
                    .buttonStyle(.plain)
            }

            Button {
                customAlertVisible = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18, weight: .medium))
                    Text("Add custom type")
                        .font(.DS.body.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(Color.DS.fg2)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color.DS.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(Color.DS.border1, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .padding(.top, 4)
        }
    }

    private func typeRow(_ type: NoteType) -> some View {
        HStack(spacing: 12) {
            Image(systemName: type.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.DS.fgOnAccent)
                .frame(width: 32, height: 32)
                .background(type.color)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(type.title)
                .font(.DS.body)
                .foregroundStyle(Color.DS.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Color.DS.fg2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.DS.bg2)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Two-way binding into `NoteTypeStyleStore` keyed by type. `nil`
    /// from the picker resets the type to its design-system default.
    private func typeColorBinding(for type: NoteType) -> Binding<String?> {
        Binding(
            get: { NoteTypeStyleStore.shared.overrides[type.rawValue] },
            set: { newValue in NoteTypeStyleStore.shared.setSwatchId(newValue, for: type) }
        )
    }
}
