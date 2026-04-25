import SwiftUI

/// The Create / Edit Note sheet — Phases C through E.2.2.
///
/// Currently scoped to:
/// - Horizontal type picker (one of the five default `NoteType`s)
/// - Title field — plain `String`, autofocused on present, styled by the
///   per-field `titleStyle: TextStyle?` (font + color apply uniformly)
/// - Optional rich-text **message** — `AttributedString` with per-character
///   runs (font + foregroundColor + size). Edited via SwiftUI's iOS 26
///   `TextEditor(text:selection:)` API.
/// - **Compact `StyleToolbar`** (Phase E.2.2) — always-visible icon bar
///   above the keyboard with `Aa` font · `●` color · `↕` size · `🖼` bg
///   buttons. Tapping a styling icon expands a single panel above the bar
///   (~70pt) with the full picker; tapping `🖼` opens the existing
///   `BackgroundPickerView` sheet (no inline panel — too much UI).
/// - **Vertical size slider** floats on the canvas right edge only when
///   the toolbar's Size panel is active.
/// - Cancel / Save buttons in the nav bar.
///
/// **Draft recovery (Phase E.2.1).** All editor state lives on
/// `NoteDraftStore.shared` rather than on this view. An accidental sheet
/// dismissal (swipe-down / tap outside) leaves the draft intact, so the
/// next FAB tap restores the user's in-progress note. Save and Cancel both
/// `clear()` the store explicitly.
///
/// Saved notes go to `TimelineStore.shared`; the timeline re-renders
/// automatically via Observation. The current wall-clock time is used as
/// the note's `time` string. Date/time picking lands when backdating ships.
struct NoteEditorScreen: View {
    @Environment(\.dismiss) private var dismiss

    /// Source of truth for every editable field — survives accidental
    /// dismissals during the same app session (see `NoteDraftStore`).
    private let draft = NoteDraftStore.shared

    @State private var isBackgroundPickerPresented = false
    /// Which of the toolbar's three styling panels is currently expanded
    /// (font/color/size) — `nil` when collapsed. The size slider on the
    /// canvas right edge is gated on `expandedPanel == .size`.
    @State private var expandedPanel: StyleToolbarPanel? = nil

    @FocusState private var focusedField: NoteEditorField?
    /// Tracks the most recently focused field so the inline `StyleToolbar`
    /// keeps a meaningful target even after the keyboard dismisses or focus
    /// momentarily drops (e.g. when presenting the Background sheet).
    @State private var lastEditedField: NoteEditorField = .title

    /// Whether the type picker is showing its full row of options or
    /// collapsed to a single chip (the current selection).
    ///
    /// **Default — based on draft state**: when the user is starting a
    /// fresh note (`draft.isEmpty`) we show the full row so the available
    /// categories are immediately discoverable. When they're resuming a
    /// retained draft (drag-dismissed earlier and re-opened) we collapse
    /// to the chosen chip — they've already committed.
    @State private var typePickerExpanded: Bool = NoteDraftStore.shared.isEmpty

    /// Drives the Cancel-button confirmation dialog. Skipped entirely
    /// when there's nothing to lose (draft is empty).
    @State private var isCancelConfirmationPresented = false

    var body: some View {
        @Bindable var draft = draft
        NavigationStack {
            // Whole content scrolls together — the type picker, title, and
            // message field share one outer ScrollView so the user can pull
            // the entire canvas up when the keyboard, toolbar, and tall
            // content combine to crowd the viewport. The TextEditor's own
            // internal scroll is disabled (see `messageEditor`) so it
            // self-sizes to its content; this one outer ScrollView is the
            // single source of vertical scroll.
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    typePicker
                    Divider().background(Color.DS.border1)
                    form
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(previewBackground)
            .overlay(alignment: .trailing) {
                // Slider sits on the visible viewport rather than inside the
                // scrollable content, so dragging the message canvas doesn't
                // carry the slider off-screen.
                if expandedPanel == .size {
                    VerticalSizeSlider(
                        value: Binding(
                            get: { draft.messageSize },
                            set: { newSize in
                                draft.messageSize = newSize
                                applyMessageSize(newSize)
                            }
                        )
                    )
                    .padding(.trailing, 4)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: expandedPanel)
            .navigationTitle(draft.isEmpty ? "New note" : "Resume draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StyleToolbar(
                    activeField: lastEditedField,
                    currentFontId: currentFontId,
                    currentColorId: currentColorId,
                    onSelectFont: handleSelectFont,
                    onSelectColor: handleSelectColor,
                    expandedPanel: $expandedPanel,
                    backgroundPreview: AnyView(backgroundIconPreview),
                    onTapBackground: { isBackgroundPickerPresented = true }
                )
            }
            .sheet(isPresented: $isBackgroundPickerPresented) {
                BackgroundPickerView(selection: $draft.background)
            }
            .confirmationDialog(
                "Discard draft?",
                isPresented: $isCancelConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Discard Draft", role: .destructive) {
                    draft.clear()
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your in-progress note will be lost.")
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear { focusedField = .title }
        .onChange(of: focusedField) { _, newValue in
            if let newValue { lastEditedField = newValue }
        }
    }

    // MARK: - Live preview background
    //
    // The editor surface previews how the saved note will render. Color
    // backgrounds tint at 0.333 opacity (matches card rendering); image
    // backgrounds fill scaled-to-fill at user-chosen opacity.

    @ViewBuilder
    private var previewBackground: some View {
        ZStack {
            Color.DS.bg1
            switch resolvedPreviewStyle {
            case .none:
                // Mirror KeepCard's default — the tag's pigment at 0.333
                // opacity — so the editor previews exactly what the saved
                // card will look like when the user hasn't picked an
                // override.
                draft.selectedType.color.opacity(0.333)
            case .color(let swatch):
                swatch.color().opacity(0.333)
            case .image(let data, let opacity):
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .opacity(opacity)
                        .clipped()
                }
            }
        }
        .ignoresSafeArea()
    }

    private var resolvedPreviewStyle: NoteBackgroundStyle {
        guard let background = draft.background else { return .none }
        switch background {
        case .color(let swatchId):
            if let swatch = PaletteRepository.shared.swatch(id: swatchId) {
                return .color(swatch)
            }
            return .none
        case .image(let img):
            return .image(data: img.imageData, opacity: img.opacity)
        }
    }

    /// 18pt-circle preview rendered into the toolbar's `🖼` icon. Tag
    /// default = the type pigment dot; explicit color = swatch dot;
    /// image = a thumbnail of the photo.
    @ViewBuilder
    private var backgroundIconPreview: some View {
        switch resolvedPreviewStyle {
        case .none:
            Circle().fill(draft.selectedType.color)
        case .color(let swatch):
            Circle().fill(swatch.color())
        case .image(let data, _):
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(Color.DS.bg2)
            }
        }
    }

    // MARK: - Type picker
    //
    // Collapsed (default): a single chip showing the selected type. Tapping
    // it expands the full row.
    // Expanded: every type listed; tapping any one of them — including the
    // currently-selected one — re-collapses. That makes the selected chip
    // its own "close" affordance, no extra X button required.

    private var typePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if typePickerExpanded {
                    ForEach(NoteType.allCases) { type in
                        TypeChip(type: type, isSelected: draft.selectedType == type) {
                            draft.selectedType = type
                            withAnimation(.easeOut(duration: 0.2)) {
                                typePickerExpanded = false
                            }
                        }
                    }
                } else {
                    TypeChip(type: draft.selectedType, isSelected: true) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            typePickerExpanded = true
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Form

    private var form: some View {
        @Bindable var draft = draft
        return VStack(alignment: .leading, spacing: 16) {
            // Title field uses the user's titleStyle (or default Inter @ 22 semibold).
            // `lineLimit(1...)` lets the title grow to as many lines as needed
            // — outer ScrollView handles overflow.
            TextField("Title", text: $draft.title, axis: .vertical)
                .font(draft.titleStyle.resolvedFont(defaultFontId: "inter", size: 22, weight: .semibold))
                .foregroundStyle(draft.titleStyle.resolvedColor(default: Color.DS.ink))
                .lineLimit(1...)
                .focused($focusedField, equals: .title)
                .submitLabel(.next)

            messageEditor
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// iOS 26 `TextEditor` bound to an `AttributedString` + selection.
    /// The `.font` and `.foregroundStyle` modifiers act as the *default*
    /// for runs without explicit attributes; per-run overrides win.
    ///
    /// `.scrollDisabled(true)` makes the editor stop being its own scroll
    /// container — instead it sizes itself to its content, and the parent
    /// `ScrollView` in `body` provides the single vertical scroll for the
    /// whole editor. Without this, nesting two scroll views would fight for
    /// the drag gesture and leave most of the screen unscrollable.
    /// The size slider is mounted at the viewport level (in `body`), not
    /// here, so it stays anchored to the visible canvas while content
    /// scrolls underneath.
    private var messageEditor: some View {
        @Bindable var draft = draft
        return ZStack(alignment: .topLeading) {
            if draft.message.characters.isEmpty {
                // TextEditor has no built-in placeholder API, so we overlay
                // one that hides as soon as the user types anything.
                Text("What's on your mind?")
                    .font(.DS.sans(size: 16, weight: .regular))
                    .foregroundStyle(Color.DS.fg2.opacity(0.7))
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $draft.message, selection: $draft.messageSelection)
                .font(.DS.sans(size: 16, weight: .regular))
                .foregroundStyle(Color.DS.ink)
                .scrollContentBackground(.hidden)  // let previewBackground show through
                .scrollDisabled(true)               // outer ScrollView scrolls
                .focused($focusedField, equals: .message)
                .frame(minHeight: 160)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: handleCancelTap)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save)
                .fontWeight(.semibold)
                .disabled(!isSaveEnabled)
        }
    }

    /// Cancel is the *intentional* discard path: it wipes the draft so the
    /// next open starts fresh. We only show the confirmation dialog when
    /// there's actually something to lose — an empty editor dismisses
    /// immediately. Drag-to-dismiss is the soft path and stays untouched
    /// (preserves the draft for accidental cases).
    private func handleCancelTap() {
        if draft.isEmpty {
            draft.clear()
            dismiss()
        } else {
            isCancelConfirmationPresented = true
        }
    }

    // MARK: - StyleToolbar plumbing

    private var currentFontId: String? {
        switch lastEditedField {
        case .title:    return draft.titleStyle?.fontId
        case .message:  return draft.messageFontId
        }
    }

    private var currentColorId: String? {
        switch lastEditedField {
        case .title:    return draft.titleStyle?.colorId
        case .message:  return draft.messageColorId
        }
    }

    private func handleSelectFont(_ id: String?) {
        switch lastEditedField {
        case .title:
            draft.titleStyle = updatedTitleStyle(fontId: id)
        case .message:
            draft.messageFontId = id
            applyMessageFont(id: id)
        }
    }

    private func handleSelectColor(_ id: String?) {
        switch lastEditedField {
        case .title:
            draft.titleStyle = updatedTitleStyle(colorId: id)
        case .message:
            draft.messageColorId = id
            applyMessageColor(id: id)
        }
    }

    /// Mutates the title's per-field `TextStyle`, collapsing empty styles to
    /// `nil` so saves don't carry meaningless overrides.
    private func updatedTitleStyle(
        fontId: String?? = nil,
        colorId: String?? = nil
    ) -> TextStyle? {
        let newFontId  = fontId ?? draft.titleStyle?.fontId
        let newColorId = colorId ?? draft.titleStyle?.colorId
        if newFontId == nil && newColorId == nil { return nil }
        return TextStyle(fontId: newFontId, colorId: newColorId)
    }

    // MARK: - Message rich-text editing
    //
    // `AttributedString.transformAttributes(in: &selection, body:)` does
    // double duty:
    //   - Range selection → mutates attrs on every character in the range.
    //   - Collapsed cursor → updates the selection's typing attributes so
    //     the next typed characters inherit the new font/color.

    private func applyMessageFont(id: String?) {
        let size = draft.messageSize
        draft.message.transformAttributes(in: &draft.messageSelection) { container in
            if let id, let def = FontRepository.shared.font(id: id) {
                container.font = def.font(size: size).weight(.regular)
            } else {
                container.font = nil
            }
        }
    }

    private func applyMessageColor(id: String?) {
        draft.message.transformAttributes(in: &draft.messageSelection) { container in
            if let id, let swatch = PaletteRepository.shared.swatch(id: id) {
                container.foregroundColor = swatch.color()
            } else {
                container.foregroundColor = nil
            }
        }
    }

    /// Apply a new font size to the current selection (or typing attrs).
    /// Keeps the user's currently chosen font family — falls back to the
    /// design-system default Inter when none is selected.
    private func applyMessageSize(_ size: CGFloat) {
        draft.message.transformAttributes(in: &draft.messageSelection) { container in
            if let fontId = draft.messageFontId,
               let def = FontRepository.shared.font(id: fontId) {
                container.font = def.font(size: size).weight(.regular)
            } else {
                container.font = .DS.sans(size: size, weight: .regular)
            }
        }
    }

    // MARK: - State

    private var isSaveEnabled: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Save

    private func save() {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        // Trim leading/trailing whitespace from the message while preserving
        // per-run attributes on the kept characters.
        let trimmedMessage = draft.message.trimmingTrailingAndLeadingWhitespace()
        let messageArg: AttributedString? = trimmedMessage.characters.isEmpty ? nil : trimmedMessage

        let content: MockNote.Content = .text(title: trimmedTitle, message: messageArg)
        let note = MockNote(
            time: currentTimeString,
            type: draft.selectedType,
            content: content,
            background: draft.background,
            titleStyle: draft.titleStyle
        )
        TimelineStore.shared.add(note)
        draft.clear()
        dismiss()
    }

    private var currentTimeString: String {
        Date.now.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
    }
}

// MARK: - AttributedString helpers

private extension AttributedString {
    /// Drops leading and trailing whitespace+newline characters, preserving
    /// per-run attributes on surviving characters. Used at save time so the
    /// message stored on the note doesn't carry stray whitespace from the
    /// `TextEditor` (matches how the prior `String?`-based flow trimmed).
    func trimmingTrailingAndLeadingWhitespace() -> AttributedString {
        var copy = self
        while let first = copy.characters.first,
              first.isWhitespace || first.isNewline {
            copy.characters.removeFirst()
        }
        while let last = copy.characters.last,
              last.isWhitespace || last.isNewline {
            copy.characters.removeLast()
        }
        return copy
    }
}

// MARK: - Previews

#Preview("Empty, light") {
    NoteEditorScreen()
}

#Preview("Empty, dark") {
    NoteEditorScreen()
        .preferredColorScheme(.dark)
}
