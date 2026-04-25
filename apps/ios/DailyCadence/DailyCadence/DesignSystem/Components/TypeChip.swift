import SwiftUI

/// A note-type picker chip used in the Create/Edit Note screen.
///
/// Matches `.type-chip` / `.type-chip.active` in `mobile.css`:
/// - Unselected: `bg-2` surface, 1pt `border-1`, 12pt radius, 72pt min-width,
///   12pt top/bottom × 14pt left/right padding, 6pt gap between icon and label
/// - Selected: ink background, ink border, white foreground
/// - Inner icon: 36pt circle in the type's soft color, 20pt SF Symbol in the
///   type's pigment color (unselected) or white-on-ink-on-circle (selected)
/// - Label: Inter 11pt 600 weight
struct TypeChip: View {
    let type: NoteType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.DS.bg2 : type.softColor)
                        .frame(width: 36, height: 36)
                    Image(systemName: type.systemImage)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(isSelected ? Color.DS.ink : type.color)
                }
                Text(type.title)
                    .font(.DS.sans(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.DS.fgOnAccent : Color.DS.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minWidth: 72)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.DS.ink : Color.DS.bg2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.DS.ink : Color.DS.border1, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .accessibilityLabel(type.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

private struct TypeChipPreviewHarness: View {
    @State private var selected: NoteType = .workout

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel("Interactive")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NoteType.allCases) { type in
                        TypeChip(type: type, isSelected: selected == type) {
                            selected = type
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            SectionLabel("All selected (for reference)")
            HStack(spacing: 8) {
                TypeChip(type: .workout, isSelected: true, action: {})
                TypeChip(type: .sleep, isSelected: true, action: {})
            }

            SectionLabel("All unselected (for reference)")
            HStack(spacing: 8) {
                TypeChip(type: .mood, isSelected: false, action: {})
                TypeChip(type: .activity, isSelected: false, action: {})
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.DS.bg1)
    }
}

#Preview("Light") {
    TypeChipPreviewHarness()
}

#Preview("Dark") {
    TypeChipPreviewHarness()
        .preferredColorScheme(.dark)
}
