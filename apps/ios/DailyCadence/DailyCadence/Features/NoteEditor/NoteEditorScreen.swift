import SwiftUI

/// The Create / Edit Note sheet — Phases C through E.1.
///
/// Currently scoped to:
/// - Horizontal type picker (one of the five default `NoteType`s)
/// - Title field (required, autofocused on present)
/// - Optional multi-line message
/// - Style row → opens `StylePickerView` to pick font + color for the title
///   and message independently (Phase E.1)
/// - Background row → opens `BackgroundPickerView` to pick a swatch or photo
///   (Phases D.1 + D.2.1)
/// - Cancel / Save buttons in the nav bar
///
/// Later phases extend this:
/// - **D.2.2** — image background crop UX (pan/zoom inside a fixed frame)
/// - **E.2** — selection-based rich text (mixed fonts/colors per run within
///   a single text field, requires iOS 18+ or UITextView wrap)
/// - Per-type fields (workout exercises, meal macros, sleep duration, mood
///   rating, activity steps) — driven by the selected `NoteType`
///
/// Saved notes go to `TimelineStore.shared`; the timeline re-renders
/// automatically via Observation. The current wall-clock time is used as
/// the note's `time` string. Date/time picking lands when backdating ships.
struct NoteEditorScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: NoteType = .mood
    @State private var title: String = ""
    @State private var message: String = ""
    @State private var background: MockNote.Background? = nil
    @State private var titleStyle: TextStyle? = nil
    @State private var messageStyle: TextStyle? = nil
    @State private var isBackgroundPickerPresented = false
    @State private var isStylePickerPresented = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                typePicker
                Divider().background(Color.DS.border1)
                form
                Divider().background(Color.DS.border1)
                styleRow
                Divider().background(Color.DS.border1)
                backgroundRow
            }
            .background(previewBackground)
            .navigationTitle("New note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $isBackgroundPickerPresented) {
                BackgroundPickerView(selection: $background)
            }
            .sheet(isPresented: $isStylePickerPresented) {
                StylePickerView(titleStyle: $titleStyle, messageStyle: $messageStyle)
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear { titleFocused = true }
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
                EmptyView()
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
        guard let background else { return .none }
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

    // MARK: - Type picker

    private var typePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NoteType.allCases) { type in
                    TypeChip(type: type, isSelected: selectedType == type) {
                        selectedType = type
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title field uses the user's titleStyle (or default Inter @ 22 semibold).
            TextField("Title", text: $title, axis: .vertical)
                .font(titleStyle.resolvedFont(defaultFontId: "inter", size: 22, weight: .semibold))
                .foregroundStyle(titleStyle.resolvedColor(default: Color.DS.ink))
                .lineLimit(1...3)
                .focused($titleFocused)
                .submitLabel(.next)

            // Message uses the user's messageStyle (or default Inter @ 16 regular).
            TextField(
                "What's on your mind?",
                text: $message,
                axis: .vertical
            )
            .font(messageStyle.resolvedFont(defaultFontId: "inter", size: 16, weight: .regular))
            .foregroundStyle(messageStyle.resolvedColor(default: Color.DS.ink))
            .lineLimit(3...12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Style row

    private var styleRow: some View {
        Button {
            isStylePickerPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "textformat")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.DS.fg2)
                Text("Style")
                    .font(.DS.body)
                    .foregroundStyle(Color.DS.ink)
                Spacer(minLength: 8)
                Text(styleSummary)
                    .font(.DS.body)
                    .foregroundStyle(Color.DS.fg2)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.DS.fg2)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var styleSummary: String {
        switch (titleStyle, messageStyle) {
        case (nil, nil):
            return "Default"
        case (.some, nil):
            return "Title styled"
        case (nil, .some):
            return "Message styled"
        case (.some, .some):
            return "Title + message styled"
        }
    }

    // MARK: - Background row

    private var backgroundRow: some View {
        Button {
            isBackgroundPickerPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.DS.fg2)
                Text("Background")
                    .font(.DS.body)
                    .foregroundStyle(Color.DS.ink)
                Spacer(minLength: 8)
                backgroundSummary
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.DS.fg2)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var backgroundSummary: some View {
        switch resolvedPreviewStyle {
        case .none:
            Text("None")
                .font(.DS.body)
                .foregroundStyle(Color.DS.fg2)
        case .color(let swatch):
            Text(swatch.name)
                .font(.DS.body)
                .foregroundStyle(Color.DS.fg2)
            Circle()
                .fill(swatch.color())
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.DS.border1, lineWidth: 1))
        case .image(let data, _):
            Text("Photo")
                .font(.DS.body)
                .foregroundStyle(Color.DS.fg2)
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.DS.border1, lineWidth: 1))
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save)
                .fontWeight(.semibold)
                .disabled(!isSaveEnabled)
        }
    }

    // MARK: - State

    private var isSaveEnabled: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Save

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let content: MockNote.Content = trimmedMessage.isEmpty
            ? .text(title: trimmedTitle, message: nil)
            : .text(title: trimmedTitle, message: trimmedMessage)

        let note = MockNote(
            time: currentTimeString,
            type: selectedType,
            content: content,
            background: background,
            titleStyle: titleStyle,
            messageStyle: messageStyle
        )
        TimelineStore.shared.add(note)
        dismiss()
    }

    private var currentTimeString: String {
        Date.now.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
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
