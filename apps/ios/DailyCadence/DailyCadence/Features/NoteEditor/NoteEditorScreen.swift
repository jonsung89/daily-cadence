import SwiftUI
import PhotosUI
import AVFoundation

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
    /// Phase E.5.22 — drives the scheme-aware default-tint opacity in
    /// the live preview background so the editor matches KeepCard's
    /// dark-mode treatment.
    @Environment(\.colorScheme) private var colorScheme

    /// When non-nil, the editor is opened in **edit mode** — pre-populated
    /// with this note's data on appear, and Save calls `TimelineStore.update`
    /// instead of `add`. Drag-to-dismiss in edit mode autosaves (Apple
    /// Notes pattern). When nil, the editor is in **create mode** — backed
    /// by `NoteDraftStore.shared` for cross-session draft recovery, and
    /// drag-to-dismiss preserves the draft (no save).
    let editing: MockNote?

    /// Source of truth for every editable field. **Create mode** uses the
    /// shared singleton so drafts survive accidental dismissals across
    /// sessions. **Edit mode** uses a per-instance store populated from
    /// `editing` so opening a note for edit doesn't trample any
    /// in-progress new-note draft (and vice versa).
    @State private var draft: NoteDraftStore

    /// Tracks whether the user explicitly committed (Save) or discarded
    /// (Cancel) before dismiss. If neither fired by the time the sheet
    /// goes away, we infer drag-to-dismiss and apply per-mode semantics
    /// (edit → autosave; create → keep draft).
    @State private var didCommit = false
    @State private var didDiscard = false

    init(editing: MockNote? = nil) {
        self.editing = editing
        let initialDraft: NoteDraftStore
        if let editing {
            let store = NoteDraftStore()
            store.populate(from: editing)
            initialDraft = store
        } else {
            initialDraft = .shared
        }
        self._draft = State(wrappedValue: initialDraft)
    }

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

    /// Phase F.1.2.picker — drives the searchable type picker sheet.
    /// The editor opens straight to writing (no picker visible);
    /// tapping the type chip near the title presents the sheet.
    /// "Combo A+B" rationale captured in PROGRESS.md.
    @State private var isTypePickerSheetPresented: Bool = false

    /// Drives the Cancel-button confirmation dialog. Skipped entirely
    /// when there's nothing to lose (draft is empty).
    @State private var isCancelConfirmationPresented = false

    /// Phase F.1.0 — drives the Delete-from-edit confirmation alert.
    /// Tapping Delete in the toolbar's actions menu sets this; the
    /// alert's destructive action calls `TimelineStore.delete` and
    /// dismisses the editor.
    @State private var isDeleteConfirmationPresented = false

    /// Phase E.5.18 — drives the inline-attachment PhotosPicker. Tap the
    /// `+image` icon in the StyleToolbar → `isImagePickerPresented = true`.
    /// Selected items run through `MediaImporter` → image goes through
    /// the crop sheet (Phase E.5.18a); videos skip cropping and insert
    /// directly via `draft.insertMedia`.
    @State private var isImagePickerPresented = false
    @State private var attachmentPickerItem: PhotosPickerItem?
    @State private var attachmentImportError: String?

    /// Phase E.5.18a — the imported (but not yet inserted) image
    /// payload + its `PhotoCropState`. Drives the crop sheet. Video
    /// imports never populate this — they bypass cropping.
    @State private var pendingCropPayload: MediaPayload?
    @State private var pendingCropState: PhotoCropState?

    /// Phase F.1.1b' — video over the duration cap. When non-nil, drives
    /// the trim sheet. Cleared on confirm or cancel.
    @State private var trimSource: MediaImporter.VideoTrimSource?

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
            .navigationTitle(navTitle)
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
                    onTapBackground: { isBackgroundPickerPresented = true },
                    onTapInsertImage: { isImagePickerPresented = true }
                )
            }
            .sheet(isPresented: $isBackgroundPickerPresented) {
                BackgroundPickerView(selection: $draft.background)
            }
            // Phase F.1.2.picker — searchable note-type picker. Tapping
            // the type chip near the title presents this; cancel keeps
            // the existing selection.
            .sheet(isPresented: $isTypePickerSheetPresented) {
                NoteTypePickerSheet(
                    selectedType: draft.selectedType,
                    onSelect: { picked in draft.selectedType = picked }
                )
            }
            .photosPicker(
                isPresented: $isImagePickerPresented,
                selection: $attachmentPickerItem,
                matching: .any(of: [.images, .videos]),
                preferredItemEncoding: .current,
                photoLibrary: .shared()
            )
            .onChange(of: attachmentPickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await importAttachment(newItem) }
            }
            // Phase E.5.18a — crop sheet, presented when an image was
            // imported and is awaiting user-confirmed cropping.
            // Re-uses the same `PhotoCropView` the bare-media editor uses.
            .sheet(isPresented: cropSheetPresented) {
                cropSheet
            }
            // Phase F.1.1b' — trim sheet for videos over the duration cap.
            .sheet(item: $trimSource) { source in
                VideoTrimSheet(
                    source: source,
                    maxDurationSeconds: MediaImporter.videoMaxDurationSeconds,
                    onCancel: { cancelTrim(source) },
                    onConfirm: { range in confirmTrim(source: source, range: range) }
                )
            }
            // Phase E.5.18c — discard confirmation is `.alert`, not
            // `.confirmationDialog`. Matches the same Apple-pattern
            // alignment we did in E.5.17 for delete: irreversible
            // single-item destruction → centered alert (Notes / Photos
            // / Calendar / Reminders), not bottom action sheet.
            .alert(
                editing == nil ? "Discard draft?" : "Discard changes?",
                isPresented: $isCancelConfirmationPresented
            ) {
                Button(
                    editing == nil ? "Discard Draft" : "Discard Changes",
                    role: .destructive
                ) {
                    draft.clear()
                    didDiscard = true
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text(editing == nil
                     ? "Your in-progress note will be lost."
                     : "Your edits to this note will be lost.")
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear { focusedField = .title }
        .onChange(of: focusedField) { _, newValue in
            if let newValue { lastEditedField = newValue }
        }
        // Phase F.1.0 — per-mode drag-to-dismiss semantics. Edit mode
        // autosaves (Apple Notes pattern); create mode keeps the draft
        // for cross-session recovery (the existing behavior).
        .onDisappear {
            if editing != nil, !didCommit, !didDiscard {
                save()
            }
        }
        // Phase F.1.0 — Delete confirmation when fired from the edit
        // toolbar's actions menu. Same Apple-pattern alignment as the
        // timeline's long-press Delete (centered alert for irreversible
        // single-item destruction).
        .alert(
            "Delete this note?",
            isPresented: $isDeleteConfirmationPresented,
            presenting: editing?.id
        ) { id in
            Button("Delete", role: .destructive) {
                TimelineStore.shared.delete(noteId: id)
                draft.clear()
                didDiscard = true
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    // MARK: - Live preview background
    //
    // The editor surface previews how the saved note will render.
    // Phase E.5.20 — type-default tints at 0.333 opacity (calm accent);
    // user-picked swatches render at FULL opacity (WYSIWYG, matches the
    // picker preview). Image backgrounds use the user-chosen opacity.

    @ViewBuilder
    private var previewBackground: some View {
        ZStack {
            Color.DS.bg1
            switch resolvedPreviewStyle {
            case .none:
                // Phase E.5.22 — mirror KeepCard's scheme-aware default
                // tint so the editor previews exactly what the saved
                // card will look like in either color scheme. Dark mode
                // drops to 0.18 to avoid muddy saturated tint.
                draft.selectedType.color.opacity(NoteType.defaultTintOpacity(for: colorScheme))
            case .color(let swatch):
                // Full opacity — matches saved KeepCard / NoteCard rendering.
                swatch.color()
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

    // MARK: - Type picker (Phase F.1.2.picker — combo A+B)
    //
    // Single chip showing the current selected type. Tap → presents
    // `NoteTypePickerSheet` (searchable + scrollable grid). The editor
    // opens straight to writing; the user only interacts with the type
    // picker when they explicitly want to change it. Scales to 7, 17,
    // or 70 types without changing this UI.

    private var typePicker: some View {
        HStack {
            TypeChip(type: draft.selectedType, isSelected: true) {
                isTypePickerSheetPresented = true
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

            attachmentsStrip

            // Phase E.5.18a — only render the trailing TextEditor once
            // there are inline media blocks. Without media, `messageEditor`
            // edits the only paragraph; both editors would be tied to
            // the same block and confuse the user.
            if draft.hasMedia {
                trailerEditor
            }

            occurredAtRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// "Type after the images" TextEditor (Phase E.5.18a). Bound to
    /// `draft.trailerMessage` (the LAST paragraph block); only rendered
    /// when `draft.hasMedia == true`. Lives below `attachmentsStrip` so
    /// the visual order matches the saved block order:
    /// `firstParagraph → media… → trailingParagraph`.
    private var trailerEditor: some View {
        @Bindable var draft = draft
        return ZStack(alignment: .topLeading) {
            if draft.trailerMessage.characters.isEmpty {
                Text("Add more thoughts…")
                    .font(.DS.sans(size: 16, weight: .regular))
                    .foregroundStyle(Color.DS.fg2.opacity(0.7))
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $draft.trailerMessage, selection: $draft.messageSelection)
                .font(.DS.sans(size: 16, weight: .regular))
                .foregroundStyle(Color.DS.ink)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($focusedField, equals: .trailer)
                // Mirrors the messageEditor's tight 40pt minHeight —
                // empty-state placeholder still readable, no wasted
                // reserved space below the photo when the user starts
                // typing in the trailer.
                .frame(minHeight: 40)
        }
    }

    /// Phase E.5.18 — vertical strip of inline media blocks rendered
    /// below the message editor. Each block has a tap-to-open `Menu`
    /// for resize (Small / Medium / Large) + remove. The data model
    /// supports interleaving media with paragraphs anywhere in the
    /// body, but this Phase 1 editor UI just appends new media after
    /// the typed paragraph — mid-paragraph insertion can come in a
    /// follow-up round once the demand is real.
    @ViewBuilder
    private var attachmentsStrip: some View {
        let mediaBlocks = draft.body.compactMap { block -> (UUID, MediaPayload, MediaBlockSize)? in
            if case .media(let payload, let size) = block.kind {
                return (block.id, payload, size)
            }
            return nil
        }
        if !mediaBlocks.isEmpty {
            VStack(spacing: 12) {
                ForEach(mediaBlocks, id: \.0) { id, payload, size in
                    attachmentRow(blockId: id, payload: payload, size: size)
                }
            }
            .transition(.opacity)
        }
        if let attachmentImportError {
            Text(attachmentImportError)
                .font(.DS.small)
                .foregroundStyle(.red)
        }
    }

    /// One inserted attachment in the editor strip. **Tap = open the
    /// fullscreen viewer; long-press = `.contextMenu` for resize / remove**
    /// (Phase E.5.18a — Apple Notes pattern). Previously this was a
    /// `Menu` wrapping the image which captured every tap; users had no
    /// way to view attachments full-screen from the editor.
    ///
    /// `InlineMediaBlockView`'s own tap-to-view behavior handles the
    /// view path (`isInteractive: true`); SwiftUI's `.contextMenu`
    /// modifier handles the long-press menu.
    private func attachmentRow(
        blockId: UUID,
        payload: MediaPayload,
        size: MediaBlockSize
    ) -> some View {
        InlineMediaBlockView(
            payload: payload,
            size: size,
            cornerRadius: 10,
            isInteractive: true
        )
        .contextMenu {
            Picker("Size", selection: sizeBinding(for: blockId)) {
                ForEach(MediaBlockSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            Divider()
            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.18)) {
                    draft.removeBlock(id: blockId)
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    /// Two-way binding for one media block's `MediaBlockSize`. Reading
    /// finds the block in `draft.body`; writing routes through
    /// `NoteDraftStore.resizeMediaBlock(id:to:)`.
    private func sizeBinding(for blockId: UUID) -> Binding<MediaBlockSize> {
        Binding(
            get: {
                for block in draft.body {
                    if block.id == blockId, case .media(_, let size) = block.kind {
                        return size
                    }
                }
                return .medium
            },
            set: { newSize in
                draft.resizeMediaBlock(id: blockId, to: newSize)
            }
        )
    }

    /// Imports a `PhotosPickerItem` via `MediaImporter`. **Images go
    /// through the crop sheet** (Phase E.5.18a — reusing
    /// `PhotoCropView` from MediaCrop); **videos under the duration cap
    /// insert directly**, and **videos over the cap** route through
    /// `VideoTrimSheet` (Phase F.1.1b'). Errors surface inline below the
    /// strip without an alert.
    private func importAttachment(_ item: PhotosPickerItem) async {
        attachmentImportError = nil
        do {
            let result = try await MediaImporter.makePayload(from: item)
            await MainActor.run {
                attachmentPickerItem = nil
                switch result {
                case .payload(let payload):
                    if payload.kind == .image,
                       let bytes = payload.data,
                       let cropState = PhotoCropState(data: bytes) {
                        // Stage for cropping. Sheet presents on the next
                        // render cycle when both fields are set.
                        pendingCropPayload = payload
                        pendingCropState = cropState
                    } else {
                        // Video (or image whose data couldn't decode) —
                        // insert directly without cropping.
                        withAnimation(.easeOut(duration: 0.2)) {
                            draft.insertMedia(payload, size: .medium)
                        }
                    }
                case .needsTrim(let source):
                    trimSource = source
                }
            }
        } catch {
            await MainActor.run {
                attachmentImportError = "Couldn't load that file. Try another one."
                attachmentPickerItem = nil
            }
        }
    }

    private func cancelTrim(_ source: MediaImporter.VideoTrimSource) {
        MediaImporter.discardTrimSource(source)
        trimSource = nil
    }

    private func confirmTrim(source: MediaImporter.VideoTrimSource, range: CMTimeRange) {
        trimSource = nil
        Task {
            do {
                let payload = try await MediaImporter.makeTrimmedVideoPayload(
                    source: source,
                    range: range
                )
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        draft.insertMedia(payload, size: .medium)
                    }
                }
            } catch {
                await MainActor.run {
                    attachmentImportError = (error as? LocalizedError)?.errorDescription
                        ?? "Couldn't trim that video. Try a different clip."
                }
            }
        }
    }

    /// User confirmed the crop. Build a fresh `MediaPayload` from the
    /// cropped data + new aspect ratio and insert as a media block.
    private func confirmCrop() {
        guard let pending = pendingCropPayload,
              let cropState = pendingCropState,
              let result = cropState.commitCrop() else {
            cancelCrop()
            return
        }
        let croppedPayload = MediaPayload(
            kind: .image,
            data: result.data,
            posterData: nil,
            aspectRatio: result.aspectRatio,
            caption: pending.caption
        )
        withAnimation(.easeOut(duration: 0.2)) {
            draft.insertMedia(croppedPayload, size: .medium)
        }
        pendingCropPayload = nil
        pendingCropState = nil
    }

    /// User cancelled the crop sheet — discard the staged image without
    /// inserting it.
    private func cancelCrop() {
        pendingCropPayload = nil
        pendingCropState = nil
    }

    /// Bool projection of the staged-crop pair for `.sheet(isPresented:)`.
    /// Resetting to `false` (e.g. via swipe-down) calls `cancelCrop()`
    /// so the staged image doesn't ghost the next picker open.
    private var cropSheetPresented: Binding<Bool> {
        Binding(
            get: { pendingCropPayload != nil && pendingCropState != nil },
            set: { if !$0 { cancelCrop() } }
        )
    }

    /// The crop sheet body. Reuses `PhotoCropView` from MediaCrop so
    /// users get the same freeform / aspect-preset chips and corner-drag
    /// crop UX as the bare-media editor.
    @ViewBuilder
    private var cropSheet: some View {
        if let cropState = pendingCropState {
            NavigationStack {
                PhotoCropView(state: cropState)
                    .padding(.top, 8)
                    .navigationTitle("Crop image")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", action: cancelCrop)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add", action: confirmCrop)
                                .fontWeight(.semibold)
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        } else {
            EmptyView()
        }
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
                // Phase E.5.18 → E.5.18d — dropped from 160 → 60 → 40.
                // 60pt still left ~25pt of empty space below a short
                // typed message before the inline image, making the
                // photo feel disconnected from the text. 40pt is tight
                // enough to wrap one-line content while still leaving
                // a clear tap target for the empty-state placeholder.
                .frame(minHeight: 40)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: handleCancelTap)
        }
        // Phase F.1.0 — edit mode adds a per-note actions menu next to
        // Save: Pin (togglable) and Delete. Surfaced here so the user
        // doesn't have to back out + long-press the card to do these.
        if editing != nil {
            ToolbarItem(placement: .topBarTrailing) {
                editActionsMenu
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(editing == nil ? "Save" : "Done", action: save)
                .fontWeight(.semibold)
                .disabled(!isSaveEnabled)
        }
    }

    /// Per-note actions menu shown in edit mode only — Pin/Unpin toggle
    /// + Delete. Pin reads through `PinStore.shared` so the label
    /// reflects the current state and tapping toggles + persists.
    /// Delete arms the same confirmation alert the timeline's long-press
    /// menu does.
    @ViewBuilder
    private var editActionsMenu: some View {
        let isPinned = editing.map { PinStore.shared.isPinned($0.id) } ?? false
        Menu {
            Button {
                if let id = editing?.id { PinStore.shared.togglePin(id) }
            } label: {
                Label(
                    isPinned ? "Unpin" : "Pin",
                    systemImage: isPinned ? "pin.slash" : "pin"
                )
            }
            Divider()
            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .regular))
        }
        .accessibilityLabel("Note actions")
    }

    /// Cancel is the *intentional* discard path: in create mode it wipes
    /// the draft so the next open starts fresh; in edit mode it discards
    /// the user's pending changes (the underlying note stays as it was).
    /// We only show the confirmation dialog when there's actually
    /// something to lose. Drag-to-dismiss is the soft path: in create
    /// mode it preserves the draft for accidental cases; in edit mode it
    /// autosaves (Apple Notes pattern) — see `.onDisappear`.
    private func handleCancelTap() {
        let isClean = (editing == nil && draft.isEmpty)
            || (editing != nil && !isDirtyVsEditing)
        if isClean {
            draft.clear()
            didDiscard = true
            dismiss()
        } else {
            isCancelConfirmationPresented = true
        }
    }

    /// Has the user changed any field versus the note we opened? Used
    /// to skip the confirmation dialog when Cancel is tapped on an
    /// untouched edit session. Compares the editable surface only —
    /// title text, body blocks, type, background, titleStyle,
    /// occurredAt. Pin state lives in `PinStore` and isn't part of
    /// the dirty check (toggling pin auto-persists separately).
    private var isDirtyVsEditing: Bool {
        guard let editing else { return false }
        if draft.selectedType != editing.type { return true }
        if draft.background != editing.background { return true }
        if draft.titleStyle != editing.titleStyle { return true }
        if draft.occurredAt != editing.occurredAt { return true }
        if case .text(let t, let blocks) = editing.content {
            if draft.title != t { return true }
            if draft.body != blocks { return true }
            return false
        }
        // Non-.text variants: any change to title/body counts as dirty.
        return draft.title != editing.timelineTitle || !draft.bodyIsEmpty
    }

    // MARK: - StyleToolbar plumbing

    private var currentFontId: String? {
        switch lastEditedField {
        case .title:                return draft.titleStyle?.fontId
        case .message, .trailer:    return draft.messageFontId
        }
    }

    private var currentColorId: String? {
        switch lastEditedField {
        case .title:                return draft.titleStyle?.colorId
        case .message, .trailer:    return draft.messageColorId
        }
    }

    private func handleSelectFont(_ id: String?) {
        switch lastEditedField {
        case .title:
            draft.titleStyle = updatedTitleStyle(fontId: id)
        case .message, .trailer:
            // Phase E.5.18a — both message and trailer paragraphs share
            // the same toolbar-mirrored font id. The actual
            // transformAttributes call applies to whichever paragraph
            // (first or last) is currently focused.
            draft.messageFontId = id
            applyMessageFont(id: id)
        }
    }

    private func handleSelectColor(_ id: String?) {
        switch lastEditedField {
        case .title:
            draft.titleStyle = updatedTitleStyle(colorId: id)
        case .message, .trailer:
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

    /// Phase E.5.18a — routes the transformAttributes call to the
    /// AttributedString of the currently focused paragraph: `.message`
    /// (first paragraph / top messageEditor) or `.trailer` (last
    /// paragraph / trailerEditor). Falls back to `.message` if neither
    /// is focused (e.g. background sheet just dismissed).
    private func transformActiveBody(_ body: (inout AttributeContainer) -> Void) {
        switch lastEditedField {
        case .trailer:
            draft.trailerMessage.transformAttributes(in: &draft.messageSelection, body: body)
        case .title, .message:
            draft.message.transformAttributes(in: &draft.messageSelection, body: body)
        }
    }

    private func applyMessageFont(id: String?) {
        let size = draft.messageSize
        transformActiveBody { container in
            if let id, let def = FontRepository.shared.font(id: id) {
                container.font = def.font(size: size).weight(.regular)
            } else {
                container.font = nil
            }
        }
    }

    private func applyMessageColor(id: String?) {
        transformActiveBody { container in
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
        transformActiveBody { container in
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

        // Phase E.5.18 — serialize the draft's block list straight into
        // `.text(title:body:)`. Each paragraph block gets its leading/
        // trailing whitespace trimmed (preserving per-run attrs on the
        // kept characters); empty paragraph blocks are dropped from the
        // saved body so a note doesn't carry phantom blank rows. Media
        // blocks pass through untouched.
        let savedBlocks: [TextBlock] = draft.body.compactMap { block in
            switch block.kind {
            case .paragraph(let text):
                let trimmed = text.trimmingTrailingAndLeadingWhitespace()
                if trimmed.characters.isEmpty { return nil }
                return TextBlock(id: block.id, kind: .paragraph(trimmed))
            case .media:
                return block
            }
        }

        let content: MockNote.Content = .text(title: trimmedTitle, body: savedBlocks)
        if let editing {
            // Edit mode — preserve the original UUID so the server-side
            // UPDATE targets the right row. Background / titleStyle /
            // type / occurredAt / content all come from the (possibly
            // modified) draft; pin state lives separately in PinStore
            // and isn't part of the MockNote shape.
            let updated = MockNote(
                id: editing.id,
                occurredAt: occurredAtForSave,
                type: draft.selectedType,
                content: content,
                background: draft.background,
                titleStyle: draft.titleStyle
            )
            TimelineStore.shared.update(updated)
            draft.clear()
            didCommit = true
            dismiss()
            return
        }
        let note = MockNote(
            occurredAt: occurredAtForSave,
            type: draft.selectedType,
            content: content,
            background: draft.background,
            titleStyle: draft.titleStyle
        )
        TimelineStore.shared.add(note)
        draft.clear()
        didCommit = true
        dismiss()
    }

    /// Edit mode shows the note's date in the nav title (Apple Notes
    /// pattern). Create mode keeps the existing "New note" / "Resume
    /// draft" labels.
    private var navTitle: String {
        if let editing {
            return editing.occurredAt?.formatted(.dateTime.month().day()) ?? "Note"
        }
        return draft.isEmpty ? "New note" : "Resume draft"
    }

    /// The timestamp stamped on `MockNote.occurredAt` when the user saves.
    /// Reads the user's date+time picker selection if they touched it,
    /// otherwise defaults to `defaultOccurredAt`.
    private var occurredAtForSave: Date {
        draft.occurredAt ?? defaultOccurredAt
    }

    /// "The day the user is viewing, at the current wall-clock time" —
    /// the editor's picker defaults to this. When the user is viewing
    /// today, that resolves to `Date.now`. When they're viewing a past
    /// day from the timeline, it splices the current time-of-day onto
    /// that day so the backdated entry lands at a believable position
    /// in that day's chronology.
    private var defaultOccurredAt: Date {
        Self.combine(day: TimelineStore.shared.selectedDate, timeOfDay: .now)
    }

    /// Splices the time-of-day from `timeOfDay` onto `day`'s calendar date.
    static func combine(day: Date, timeOfDay: Date) -> Date {
        let cal = Calendar.current
        let timeComps = cal.dateComponents([.hour, .minute, .second], from: timeOfDay)
        return cal.date(
            bySettingHour: timeComps.hour ?? 0,
            minute: timeComps.minute ?? 0,
            second: timeComps.second ?? 0,
            of: day
        ) ?? day
    }

    /// Phase F.0.3 — date + time picker row at the bottom of the form.
    /// Bound to `draft.occurredAt` via a computed binding that falls back
    /// to `defaultOccurredAt`. SwiftUI's `.compact` style renders as a
    /// single line that opens a popover with a calendar grid + time
    /// wheels — Apple-standard daily picker.
    private var occurredAtRow: some View {
        @Bindable var draft = draft
        return HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.DS.fg2)
            Text("Time")
                .font(.DS.body)
                .foregroundStyle(Color.DS.ink)
            Spacer(minLength: 8)
            DatePicker(
                "Time",
                selection: Binding(
                    get: { draft.occurredAt ?? defaultOccurredAt },
                    set: { draft.occurredAt = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
        .padding(.top, 8)
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
