import SwiftUI

/// Which text field a styling action targets.
///
/// Defined here (not as a nested type) so both `NoteEditorScreen` (owner of
/// the `@FocusState`) and `StyleToolbar` (the inline picker) can refer to
/// the same enum without an import dance.
enum NoteEditorField: Hashable {
    case title
    case message
}

/// Which expanded panel — if any — is currently visible above the icon bar.
///
/// Hoisted into the editor (rather than owned by the toolbar) so external
/// affordances can drive it: the size slider on the canvas edge is only
/// shown when `expandedPanel == .size`, the editor-level `bg` icon opens
/// the existing `BackgroundPickerView` sheet rather than an inline panel,
/// and so on.
enum StyleToolbarPanel: Hashable {
    case font
    case color
    case size
}

/// Always-visible style toolbar pinned above the keyboard inside
/// `NoteEditorScreen`. **Phase E.2.2** redesigned this from a tall
/// always-on tray (~150pt) to a compact icon bar (~48pt) plus an
/// optional expanded panel (~70pt) — the canvas reclaims ~100pt when no
/// picker is open, which matters a lot on smaller phones.
///
/// **Layout**
/// ```
/// ┌──────────────────────────────────────────────┐ ← optional expanded
/// │ FONT · MESSAGE                               │   panel (~70pt) —
/// │ [Default] [Inter] [Playfair] [New York] …    │   only when
/// └──────────────────────────────────────────────┘   `expandedPanel != nil`
/// │ [Aa] [●] [↕]                       [🖼]      │ ← always-on icon
/// └──────────────────────────────────────────────┘   bar (~48pt)
/// ```
///
/// **Interaction**
/// - Tap `Aa` / `●` / `↕` → toggles its expanded panel (closes any other).
/// - Tap `🖼` → opens the existing `BackgroundPickerView` sheet (no inline
///   panel — too much UI for the bar with photo picker + opacity).
/// - The size slider lives on the canvas right edge (Instagram-Story
///   aesthetic, kept) but only renders when `expandedPanel == .size`.
///
/// **Active-target indication.** The "STYLING TITLE/MESSAGE" label moved
/// into the expanded panel's header so the icon bar stays minimal. The
/// cursor in the editor canvas already tells the user which field is
/// focused, so the label is only useful when a picker is actually open.
struct StyleToolbar: View {
    let activeField: NoteEditorField
    let currentFontId: String?
    let currentColorId: String?
    let onSelectFont: (String?) -> Void
    let onSelectColor: (String?) -> Void
    @Binding var expandedPanel: StyleToolbarPanel?
    /// Caller-provided preview content for the Background icon — usually a
    /// small swatch dot or photo thumbnail. The toolbar doesn't know about
    /// `MockNote.Background`; the editor renders the right preview.
    let backgroundPreview: AnyView
    let onTapBackground: () -> Void

    private let fonts: [NoteFontDefinition]
    private let swatches: [Swatch]

    init(
        activeField: NoteEditorField,
        currentFontId: String?,
        currentColorId: String?,
        onSelectFont: @escaping (String?) -> Void,
        onSelectColor: @escaping (String?) -> Void,
        expandedPanel: Binding<StyleToolbarPanel?>,
        backgroundPreview: AnyView,
        onTapBackground: @escaping () -> Void,
        fontRepository: FontRepository = .shared,
        paletteRepository: PaletteRepository = .shared
    ) {
        self.activeField = activeField
        self.currentFontId = currentFontId
        self.currentColorId = currentColorId
        self.onSelectFont = onSelectFont
        self.onSelectColor = onSelectColor
        self._expandedPanel = expandedPanel
        self.backgroundPreview = backgroundPreview
        self.onTapBackground = onTapBackground
        self.fonts = fontRepository.allFonts()
        self.swatches = paletteRepository.allSwatches()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let panel = expandedPanel {
                expandedPanelView(panel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            iconBar
        }
        .background(toolbarBackground)
        .animation(.easeOut(duration: 0.2), value: expandedPanel)
    }

    // MARK: - Icon bar

    private var iconBar: some View {
        HStack(spacing: 6) {
            fontIcon
            colorIcon
            sizeIcon
            Spacer(minLength: 0)
            backgroundIcon
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)  // clear the keyboard's top edge
        .frame(height: 56)
    }

    private var fontIcon: some View {
        iconButton(isActive: expandedPanel == .font, action: { toggle(.font) }) {
            // Show "Aa" rendered in the user's current font so the icon
            // doubles as a live preview of the active choice.
            let def = currentFontId.flatMap { FontRepository.shared.font(id: $0) }
            Text("Aa")
                .font(def?.font(size: 17).weight(.semibold) ?? .system(size: 17, weight: .semibold))
                .foregroundStyle(expandedPanel == .font ? Color.DS.bg2 : Color.DS.ink)
        }
        .accessibilityLabel("Font")
    }

    private var colorIcon: some View {
        iconButton(isActive: expandedPanel == .color, action: { toggle(.color) }) {
            ZStack {
                let swatch = currentColorId.flatMap { PaletteRepository.shared.swatch(id: $0) }
                Circle()
                    .fill(swatch?.color() ?? Color.DS.bg1)
                    .frame(width: 18, height: 18)
                if swatch == nil {
                    // Slash convention for "no color override," matching the
                    // expanded color row's Default dot.
                    Image(systemName: "line.diagonal")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(expandedPanel == .color ? Color.DS.bg2 : Color.DS.fg2)
                }
                Circle()
                    .strokeBorder(
                        expandedPanel == .color ? Color.DS.bg2 : Color.DS.border1,
                        lineWidth: 1
                    )
                    .frame(width: 20, height: 20)
            }
        }
        .accessibilityLabel("Text color")
    }

    private var sizeIcon: some View {
        iconButton(isActive: expandedPanel == .size, action: { toggle(.size) }) {
            // Two stacked "A" glyphs imply scale — small over large is the
            // common typographic affordance for "size."
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("A")
                    .font(.system(size: 11, weight: .semibold))
                Text("A")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(expandedPanel == .size ? Color.DS.bg2 : Color.DS.ink)
        }
        .accessibilityLabel("Text size")
    }

    private var backgroundIcon: some View {
        Button(action: onTapBackground) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.DS.bg1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.DS.border1, lineWidth: 0.5)
                    }
                backgroundPreview
                    .frame(width: 18, height: 18)
                    .clipShape(Circle())
            }
            .frame(width: 44, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Background")
    }

    /// Generic icon-bar button used for font / color / size. Active state
    /// fills with `ink` so the user can see at a glance which panel is
    /// open.
    private func iconButton<Content: View>(
        isActive: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: 44, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? Color.DS.ink : Color.DS.bg1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isActive ? Color.clear : Color.DS.border1,
                            lineWidth: 0.5
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func toggle(_ panel: StyleToolbarPanel) {
        expandedPanel = (expandedPanel == panel) ? nil : panel
    }

    // MARK: - Expanded panel

    @ViewBuilder
    private func expandedPanelView(_ panel: StyleToolbarPanel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            panelHeader(for: panel)
            switch panel {
            case .font:    fontRow
            case .color:   colorRow
            case .size:    sizeRowHint
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            // Hairline separator below the panel header zone — visually
            // signals "this panel sits on top of the icon bar."
            EmptyView()
        }
    }

    private func panelHeader(for panel: StyleToolbarPanel) -> some View {
        HStack(spacing: 6) {
            Text(panel.headerLabel)
                .foregroundStyle(Color.DS.ink)
            Text("·")
                .foregroundStyle(Color.DS.fg2)
            Text(activeField == .message ? "Message" : "Title")
                .foregroundStyle(Color.DS.fg2)
        }
        .font(.system(size: 10, weight: .semibold))
        .tracking(1.4)
        .textCase(.uppercase)
        .padding(.horizontal, 16)
    }

    // MARK: - Font row

    private var fontRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                fontChip(
                    label: "Default",
                    font: .system(size: 16, weight: .semibold),
                    isSelected: currentFontId == nil,
                    onTap: { onSelectFont(nil) }
                )
                ForEach(fonts) { def in
                    fontChip(
                        label: def.displayName,
                        font: def.font(size: 16).weight(.semibold),
                        isSelected: currentFontId == def.id,
                        onTap: { onSelectFont(def.id) }
                    )
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func fontChip(
        label: String,
        font: Font,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            Text(label)
                .font(font)
                .foregroundStyle(isSelected ? Color.DS.bg2 : Color.DS.ink)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.DS.ink : Color.DS.bg1)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.clear : Color.DS.border1,
                            lineWidth: 0.5
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Color row

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                colorDot(
                    isSelected: currentColorId == nil,
                    fill: nil,
                    accessibilityLabel: "Default color",
                    onTap: { onSelectColor(nil) }
                )
                ForEach(swatches) { swatch in
                    colorDot(
                        isSelected: currentColorId == swatch.id,
                        fill: swatch.color(),
                        accessibilityLabel: swatch.name,
                        onTap: { onSelectColor(swatch.id) }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
        }
    }

    private func colorDot(
        isSelected: Bool,
        fill: Color?,
        accessibilityLabel: String,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(fill ?? Color.DS.bg1)
                    .frame(width: 26, height: 26)
                if fill == nil {
                    Image(systemName: "line.diagonal")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color.DS.fg2)
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        isSelected ? Color.DS.ink : Color.DS.border1,
                        lineWidth: isSelected ? 2 : 0.5
                    )
                    .frame(width: 30, height: 30)
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Size hint

    /// The size slider lives on the canvas right edge (Instagram-Story
    /// aesthetic). The expanded panel for `.size` just shows a one-line
    /// hint so users know where the actual control is — the panel itself
    /// only signals "size mode is active" via its presence.
    private var sizeRowHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.and.right")
                .rotationEffect(.degrees(90))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.DS.fg2)
            Text("Drag the slider on the right to resize.")
                .font(.system(size: 13))
                .foregroundStyle(Color.DS.fg2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Background

    @ViewBuilder
    private var toolbarBackground: some View {
        ZStack(alignment: .top) {
            Color.DS.bg2
            Rectangle()
                .fill(Color.DS.border1)
                .frame(height: 0.5)
        }
    }
}

// MARK: - Panel labels

private extension StyleToolbarPanel {
    var headerLabel: String {
        switch self {
        case .font:   return "Font"
        case .color:  return "Color"
        case .size:   return "Size"
        }
    }
}

// MARK: - Previews

private struct StyleToolbarPreviewHarness: View {
    @State private var titleFontId: String? = nil
    @State private var titleColorId: String? = nil
    @State private var field: NoteEditorField = .title
    @State private var expanded: StyleToolbarPanel? = nil

    var body: some View {
        VStack(spacing: 0) {
            Picker("Field", selection: $field) {
                Text("Title").tag(NoteEditorField.title)
                Text("Message").tag(NoteEditorField.message)
            }
            .pickerStyle(.segmented)
            .padding()
            Spacer()
            StyleToolbar(
                activeField: field,
                currentFontId: titleFontId,
                currentColorId: titleColorId,
                onSelectFont: { titleFontId = $0 },
                onSelectColor: { titleColorId = $0 },
                expandedPanel: $expanded,
                backgroundPreview: AnyView(
                    Circle().fill(Color.DS.sage)
                ),
                onTapBackground: {}
            )
        }
        .background(Color.DS.bg1)
    }
}

#Preview("Light") {
    StyleToolbarPreviewHarness()
}

#Preview("Dark") {
    StyleToolbarPreviewHarness()
        .preferredColorScheme(.dark)
}
