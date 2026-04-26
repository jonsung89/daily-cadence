import SwiftUI

/// Which text field a styling action targets.
///
/// Defined here (not as a nested type) so both `NoteEditorScreen` (owner of
/// the `@FocusState`) and `StyleToolbar` (the inline picker) can refer to
/// the same enum without an import dance.
///
/// **Phase E.5.18a — `.trailer` case.** Once a note carries inline media,
/// the editor renders a second TextEditor below the attachments strip
/// for "type after the images." `.message` continues to mean the first
/// paragraph (the existing top messageEditor); `.trailer` means the
/// last paragraph (the new trailing editor below the photos). The
/// StyleToolbar treats both as message-style body text.
enum NoteEditorField: Hashable {
    case title
    case message
    case trailer
}

extension NoteEditorField {
    /// True when the field is one of the body-text editors (message or
    /// trailer) — i.e., styling should treat it as "message," not title.
    var isBodyText: Bool {
        self == .message || self == .trailer
    }
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
    /// Phase E.5.18 — `+image` button. Fires when the user taps it to
    /// insert an inline media block into the note's body. Optional so
    /// callers that don't support inline attachments can omit the icon.
    let onTapInsertImage: (() -> Void)?

    private let fonts: [NoteFontDefinition]
    private let swatches: [Swatch]
    private let essentialSwatches: [Swatch]

    init(
        activeField: NoteEditorField,
        currentFontId: String?,
        currentColorId: String?,
        onSelectFont: @escaping (String?) -> Void,
        onSelectColor: @escaping (String?) -> Void,
        expandedPanel: Binding<StyleToolbarPanel?>,
        backgroundPreview: AnyView,
        onTapBackground: @escaping () -> Void,
        onTapInsertImage: (() -> Void)? = nil,
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
        self.onTapInsertImage = onTapInsertImage
        self.fonts = fontRepository.allFonts()
        self.swatches = paletteRepository.allSwatches()
        self.essentialSwatches = paletteRepository.essentialSwatches()
    }

    var body: some View {
        // Phase E.5.19 — floating-pill style (Apple Notes / Mail / Reminders
        // iOS 17+ pattern). Each piece (expanded panel + icon bar) is its
        // own glass-backed RoundedRectangle floating above the keyboard
        // with horizontal inset, replacing the prior flush rectangle that
        // visually divided the canvas.
        VStack(spacing: 8) {
            if let panel = expandedPanel {
                expandedPanelView(panel)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(toolbarPillBackground)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            iconBar
                .background(toolbarPillBackground)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.2), value: expandedPanel)
    }

    /// Reusable floating-pill background — iOS 26 "Liquid Glass" style.
    ///
    /// Layered look:
    /// 1. **`.ultraThinMaterial` fill** — the translucent base that auto-
    ///    adapts to light/dark and shows what's behind through frosted blur.
    /// 2. **Inner rim highlight** — a top-to-bottom white gradient stroked
    ///    on the edge that catches the "light" the way Apple's iOS 26 glass
    ///    surfaces do (most visible on the upper edge). Without this the
    ///    pill reads as a tinted rectangle rather than a glass surface.
    /// 3. **Hairline outer border** — very subtle (`border1` @ 0.25)
    ///    grounds the pill against any backdrop without competing with
    ///    the rim highlight.
    /// 4. **Soft drop shadow** — slight lift off the keyboard, also iOS 26.
    private var toolbarPillBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)
            // Inner rim highlight — the iOS 26 glass "edge catches the light" effect.
            .overlay(
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.32),
                                Color.white.opacity(0.06),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            )
            // Outermost hairline grounds the pill against any backdrop.
            .overlay(
                shape.strokeBorder(Color.DS.border1.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    // MARK: - Icon bar

    private var iconBar: some View {
        // Phase E.5.19 — fits inside the floating pill with horizontal
        // padding for icon-to-edge breathing room. Outer pill background
        // is applied in `body`. Vertical padding compresses since the
        // pill itself sits above the keyboard with its own spacing.
        HStack(spacing: 4) {
            fontIcon
            colorIcon
            sizeIcon
            Spacer(minLength: 0)
            if onTapInsertImage != nil {
                insertImageIcon
            }
            backgroundIcon
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    /// Phase E.5.18 / E.5.19 — `+image` icon, bare on the floating
    /// pill. Fires `onTapInsertImage` to start the inline-media
    /// insertion flow (typically a PhotosPicker in the editor).
    private var insertImageIcon: some View {
        Button(action: { onTapInsertImage?() }) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.DS.ink)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Insert image")
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
        // Phase E.5.19 — bare on glass to match the other icons in the
        // floating pill. The preview swatch/dot itself is the visual
        // affordance; no surrounding chip.
        Button(action: onTapBackground) {
            backgroundPreview
                .frame(width: 22, height: 22)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.DS.border1.opacity(0.6), lineWidth: 0.5)
                )
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Background")
    }

    /// Generic icon-bar button used for font / color / size.
    /// **Phase E.5.19** — bare on the floating pill's glass surface.
    /// Active state still fills with `ink` so the user can see at a
    /// glance which panel is open; inactive state has no background
    /// chip (the pill itself supplies the visual container — Apple
    /// Notes / Mail floating-toolbar pattern).
    private func iconButton<Content: View>(
        isActive: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: 44, height: 36)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.DS.ink)
                    }
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
                // Default (slash glyph) — clears any per-note color override.
                colorDot(
                    isSelected: currentColorId == nil,
                    fill: nil,
                    accessibilityLabel: "Default color",
                    onTap: { onSelectColor(nil) }
                )
                // Phase E.5.21 — essentials (white + black) shown before
                // the palette swatches so high-contrast picks are always
                // immediately reachable. They're synthetic swatches —
                // resolvable via PaletteRepository.swatch(id:) but not
                // part of any palette tab.
                ForEach(essentialSwatches) { swatch in
                    colorDot(
                        isSelected: currentColorId == swatch.id,
                        fill: swatch.color(),
                        accessibilityLabel: swatch.name,
                        onTap: { onSelectColor(swatch.id) }
                    )
                }
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

    // (Phase E.5.19 removed the legacy flush `toolbarBackground`. The
    // floating pills carry their own `toolbarPillBackground` in `body`.)
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
