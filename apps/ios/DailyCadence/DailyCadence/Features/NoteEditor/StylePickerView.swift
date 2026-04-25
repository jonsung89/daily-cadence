import SwiftUI

/// Sheet for picking the per-field font + color of a note's text.
///
/// Two sections: **Title** and **Message**, each with a Font picker and a
/// Color picker row. Tapping a row pushes a detail screen with the list.
///
/// Phase E.1 ships per-field styling — one font and one color for the title,
/// another for the message. True rich text (mixed runs within one paragraph)
/// is deferred to Phase E.2.
struct StylePickerView: View {
    @Binding var titleStyle: TextStyle?
    @Binding var messageStyle: TextStyle?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                section(
                    header: "Title",
                    style: $titleStyle,
                    sampleText: "Sample title",
                    defaultFontId: "inter",
                    sampleSize: 22,
                    sampleWeight: .semibold,
                    defaultColor: Color.DS.ink
                )

                section(
                    header: "Message",
                    style: $messageStyle,
                    sampleText: "Sample message text",
                    defaultFontId: "inter",
                    sampleSize: 16,
                    sampleWeight: .regular,
                    defaultColor: Color.DS.fg2
                )
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.DS.bg1)
            .navigationTitle("Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func section(
        header: String,
        style: Binding<TextStyle?>,
        sampleText: String,
        defaultFontId: String,
        sampleSize: CGFloat,
        sampleWeight: Font.Weight,
        defaultColor: Color
    ) -> some View {
        Section {
            // Live preview row at the top of each section so users see
            // what they're styling without leaving the screen.
            HStack {
                Text(sampleText)
                    .font(style.wrappedValue.resolvedFont(
                        defaultFontId: defaultFontId,
                        size: sampleSize,
                        weight: sampleWeight
                    ))
                    .foregroundStyle(style.wrappedValue.resolvedColor(default: defaultColor))
                    .lineLimit(1)
                Spacer()
            }
            .listRowBackground(Color.DS.bg2)

            NavigationLink {
                FontPickerScreen(selectedFontId: fontIdBinding(for: style))
            } label: {
                HStack {
                    Text("Font")
                        .foregroundStyle(Color.DS.ink)
                    Spacer()
                    Text(fontDisplayName(for: style.wrappedValue))
                        .foregroundStyle(Color.DS.fg2)
                }
            }
            .listRowBackground(Color.DS.bg2)

            NavigationLink {
                TextColorPickerScreen(selectedColorId: colorIdBinding(for: style))
            } label: {
                HStack(spacing: 12) {
                    Text("Color")
                        .foregroundStyle(Color.DS.ink)
                    Spacer()
                    if let swatch = style.wrappedValue?.resolvedSwatch() {
                        Text(swatch.name)
                            .foregroundStyle(Color.DS.fg2)
                        Circle()
                            .fill(swatch.color())
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.DS.border1, lineWidth: 1))
                    } else {
                        Text("Default")
                            .foregroundStyle(Color.DS.fg2)
                    }
                }
            }
            .listRowBackground(Color.DS.bg2)
        } header: {
            Text(header)
        }
    }

    private func fontDisplayName(for style: TextStyle?) -> String {
        guard let definition = style?.resolvedFontDefinition() else { return "Default" }
        return definition.displayName
    }

    /// Two-way binding from `TextStyle?.fontId` so detail screens can update it.
    private func fontIdBinding(for style: Binding<TextStyle?>) -> Binding<String?> {
        Binding(
            get: { style.wrappedValue?.fontId },
            set: { newId in style.wrappedValue = updatedStyle(style.wrappedValue, fontId: newId) }
        )
    }

    private func colorIdBinding(for style: Binding<TextStyle?>) -> Binding<String?> {
        Binding(
            get: { style.wrappedValue?.colorId },
            set: { newId in style.wrappedValue = updatedStyle(style.wrappedValue, colorId: newId) }
        )
    }

    /// Build a new TextStyle reflecting the change, or nil if both fields
    /// would be empty (keeps persistence clean).
    private func updatedStyle(
        _ current: TextStyle?,
        fontId: String?? = nil,
        colorId: String?? = nil
    ) -> TextStyle? {
        let newFontId  = fontId ?? current?.fontId
        let newColorId = colorId ?? current?.colorId
        if newFontId == nil && newColorId == nil { return nil }
        return TextStyle(fontId: newFontId, colorId: newColorId)
    }
}

// MARK: - Font picker

/// Detail screen pushed from `StylePickerView` to pick a font.
struct FontPickerScreen: View {
    @Binding var selectedFontId: String?

    private let fonts: [NoteFontDefinition]

    init(
        selectedFontId: Binding<String?>,
        repository: FontRepository = .shared
    ) {
        self._selectedFontId = selectedFontId
        self.fonts = repository.allFonts()
    }

    var body: some View {
        List {
            Section {
                Button {
                    selectedFontId = nil
                } label: {
                    HStack {
                        Text("Default")
                            .foregroundStyle(Color.DS.ink)
                        Spacer()
                        if selectedFontId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.DS.sage)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.DS.bg2)
            }

            Section {
                ForEach(fonts) { font in
                    fontRow(font)
                }
            } header: {
                Text("Fonts")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.DS.bg1)
        .navigationTitle("Font")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fontRow(_ font: NoteFontDefinition) -> some View {
        Button {
            selectedFontId = font.id
        } label: {
            HStack(spacing: 12) {
                Text("Aa")
                    .font(font.font(size: 22))
                    .foregroundStyle(Color.DS.ink)
                    .frame(width: 40, alignment: .leading)
                Text(font.displayName)
                    .foregroundStyle(Color.DS.ink)
                Spacer()
                if selectedFontId == font.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.DS.sage)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.DS.bg2)
        .accessibilityLabel(font.displayName)
        .accessibilityAddTraits(selectedFontId == font.id ? .isSelected : [])
    }
}

// MARK: - Color picker

/// Detail screen pushed from `StylePickerView` to pick a text color from
/// any palette. Reuses the same swatch repository as backgrounds — colors
/// are full-saturation when applied to text (no 0.333 opacity scaling).
///
/// Reused by Settings → Note Types → \<Type> for picking type-color
/// overrides. The `title` parameter lets the caller customize the nav bar
/// header ("Color", "Workout color", etc.).
struct TextColorPickerScreen: View {
    @Binding var selectedColorId: String?
    let title: String

    private let palettes: [ColorPalette]

    init(
        selectedColorId: Binding<String?>,
        title: String = "Color",
        repository: PaletteRepository = .shared
    ) {
        self._selectedColorId = selectedColorId
        self.title = title
        self.palettes = repository.allPalettes()
    }

    var body: some View {
        List {
            Section {
                Button {
                    selectedColorId = nil
                } label: {
                    HStack {
                        Text("Default")
                            .foregroundStyle(Color.DS.ink)
                        Spacer()
                        if selectedColorId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.DS.sage)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.DS.bg2)
            }

            ForEach(palettes) { palette in
                Section {
                    ForEach(palette.swatches) { swatch in
                        swatchRow(swatch)
                    }
                } header: {
                    Text(palette.name)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.DS.bg1)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // 60pt of clear scroll padding at the bottom so the last palette's
        // bottom row can scroll fully above the translucent TabBar (when
        // pushed from Settings) or the home-indicator zone (when pushed
        // from the editor's Style sheet). Earlier `.contentMargins` attempt
        // wasn't reliable on `List`; `safeAreaInset` is.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 60)
        }
    }

    private func swatchRow(_ swatch: Swatch) -> some View {
        Button {
            selectedColorId = swatch.id
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(swatch.color())
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.DS.border1, lineWidth: 1))
                Text(swatch.name)
                    .foregroundStyle(swatch.color())
                Spacer()
                if selectedColorId == swatch.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.DS.sage)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.DS.bg2)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(selectedColorId == swatch.id ? .isSelected : [])
    }
}

// MARK: - Previews

private struct StylePickerPreviewHarness: View {
    @State private var titleStyle: TextStyle? = nil
    @State private var messageStyle: TextStyle? = nil

    var body: some View {
        StylePickerView(titleStyle: $titleStyle, messageStyle: $messageStyle)
    }
}

#Preview("Light") {
    StylePickerPreviewHarness()
}

#Preview("Dark") {
    StylePickerPreviewHarness()
        .preferredColorScheme(.dark)
}
