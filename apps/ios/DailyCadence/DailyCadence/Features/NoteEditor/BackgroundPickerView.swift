import SwiftUI
import PhotosUI

/// Sheet pushed from the Note Editor to pick a per-note background.
///
/// Sections (top to bottom):
/// 1. **None** — clears any background
/// 2. **Photo** — `PhotosPicker` to select an image, opacity slider when set
/// 3. **Color** — tabbed palettes + swatch grid (Phase D.1)
///
/// Photo and Color are mutually exclusive (one background per note). Tapping
/// any option supersedes the previous selection.
///
/// **Phase D.2.2 — interactive crop.** Picking a photo downscales it to
/// 1024px max longest edge, then auto-launches `PhotoCropView` (the same
/// crop tool media notes use) so the user picks a region + aspect.
/// Subsequent edits go through the same sheet via the "Edit crop" button.
/// The cropped bytes replace the stored `imageData`; cards still render
/// `.scaledToFill().clipped()` against those bytes.
struct BackgroundPickerView: View {
    @Binding var selection: MockNote.Background?
    @Environment(\.dismiss) private var dismiss

    @State private var activePaletteId: String
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false

    /// Active `PhotoCropState` while the crop sheet is presented. Set
    /// either by `loadPhoto` (auto-launch on first pick) or by the
    /// "Edit crop" button. Cleared on commit / cancel.
    @State private var cropState: PhotoCropState?

    /// Maximum longest-edge size for stored background images. 1024 is
    /// plenty for cards (which never exceed ~400pt × 480pt onscreen) and
    /// keeps memory + future Supabase Storage costs tight.
    private let backgroundMaxDimension: CGFloat = 1024

    private let palettes: [ColorPalette]

    init(
        selection: Binding<MockNote.Background?>,
        repository: PaletteRepository = .shared
    ) {
        self._selection = selection
        self.palettes = repository.allPalettes()

        // Start on the palette containing the current selection if any,
        // otherwise the first declared palette ("neutral").
        let activeId: String = {
            if case .color(let swatchId) = selection.wrappedValue,
               let palette = repository.allPalettes().first(where: { $0.swatches.contains(where: { $0.id == swatchId }) }) {
                return palette.id
            }
            return repository.allPalettes().first?.id ?? "neutral"
        }()
        _activePaletteId = State(initialValue: activeId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    noneRow
                    Divider().background(Color.DS.border1)
                    photoSection
                        .padding(.vertical, 8)
                    Divider().background(Color.DS.border1)
                    colorSection
                        .padding(.top, 12)
                }
            }
            .background(Color.DS.bg1)
            .navigationTitle("Background")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: photoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadPhoto(newItem) }
            }
            .sheet(isPresented: cropSheetBinding) { cropSheet }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    // MARK: - Crop sheet

    private var cropSheetBinding: Binding<Bool> {
        Binding(
            get: { cropState != nil },
            set: { if !$0 { cropState = nil } }
        )
    }

    @ViewBuilder
    private var cropSheet: some View {
        if let cropState {
            NavigationStack {
                PhotoCropView(state: cropState)
                    .padding(.top, 8)
                    .navigationTitle("Crop photo")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { self.cropState = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: confirmCrop)
                                .fontWeight(.semibold)
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// User tapped "Edit crop" — re-open the crop sheet on the current
    /// background bytes so they can refine the framing.
    private func openCropForCurrent() {
        guard case .image(let img) = selection else { return }
        cropState = PhotoCropState(data: img.imageData)
    }

    /// Commit-side of the crop sheet. Replaces the stored `imageData`
    /// with the crop result, preserves opacity. If the commit fails (e.g.
    /// degenerate crop rect), fall through and just close the sheet —
    /// the previous data stays intact.
    private func confirmCrop() {
        defer { cropState = nil }
        guard let cropState,
              case .image(let img) = selection,
              let result = cropState.commitCrop()
        else { return }
        selection = .image(MockNote.ImageBackground(
            imageData: result.data,
            opacity: img.opacity
        ))
    }

    // MARK: - None row

    private var noneRow: some View {
        Button {
            selection = nil
            photoPickerItem = nil
        } label: {
            HStack(spacing: 12) {
                noneSwatch
                Text("None")
                    .font(.DS.body)
                    .foregroundStyle(Color.DS.ink)
                Spacer(minLength: 8)
                if selection == nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.DS.sage)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("No background")
        .accessibilityAddTraits(selection == nil ? .isSelected : [])
    }

    /// A 32pt rounded square with a diagonal slash — the iOS convention for
    /// "no fill / cleared selection."
    private var noneSwatch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.DS.bg2)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.DS.border1, lineWidth: 1)
            GeometryReader { geo in
                Path { path in
                    path.move(to: CGPoint(x: 4, y: geo.size.height - 4))
                    path.addLine(to: CGPoint(x: geo.size.width - 4, y: 4))
                }
                .stroke(Color.DS.border2, lineWidth: 1.5)
            }
        }
        .frame(width: 32, height: 32)
    }

    // MARK: - Photo section

    @ViewBuilder
    private var photoSection: some View {
        if let imageBg = currentImageBackground, let uiImage = UIImage(data: imageBg.imageData) {
            VStack(alignment: .leading, spacing: 12) {
                photoPreview(uiImage: uiImage, opacity: imageBg.opacity)

                opacitySlider(currentOpacity: imageBg.opacity)

                HStack(spacing: 16) {
                    PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Replace", systemImage: "photo.on.rectangle")
                            .font(.DS.label)
                    }
                    Button(action: openCropForCurrent) {
                        Label("Edit crop", systemImage: "crop")
                            .font(.DS.label)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        selection = nil
                        photoPickerItem = nil
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.DS.label)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        } else {
            PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color.DS.fg2)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isLoadingPhoto ? "Loading photo…" : "Choose a photo")
                            .font(.DS.body)
                            .foregroundStyle(Color.DS.ink)
                        Text("Pick from your library — fills the card behind your text")
                            .font(.DS.small)
                            .foregroundStyle(Color.DS.fg2)
                    }
                    Spacer(minLength: 8)
                    if isLoadingPhoto {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.DS.fg2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLoadingPhoto)
        }
    }

    private func photoPreview(uiImage: UIImage, opacity: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.DS.bg2)
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .opacity(opacity)
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipped()
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.DS.border1, lineWidth: 1)
        )
    }

    private func opacitySlider(currentOpacity: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Opacity")
                    .font(.DS.label)
                    .foregroundStyle(Color.DS.ink)
                Spacer()
                Text("\(Int((currentOpacity * 100).rounded()))%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.DS.fg2)
            }
            Slider(
                value: Binding(
                    get: { currentOpacity },
                    set: { newValue in
                        if case .image(var img) = selection {
                            img.opacity = newValue
                            selection = .image(img)
                        }
                    }
                ),
                in: 0.1...1.0
            )
            .tint(Color.DS.sage)
        }
    }

    private var currentImageBackground: MockNote.ImageBackground? {
        guard case .image(let img) = selection else { return nil }
        return img
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        await MainActor.run { isLoadingPhoto = true }
        defer { Task { @MainActor in isLoadingPhoto = false } }

        guard let raw = try? await item.loadTransferable(type: Data.self) else { return }
        // Downscale before storing so a 4032×3024 HEIC doesn't sit in the
        // background slot — backgrounds never render larger than card-sized.
        let downscaled = MediaImporter.downscale(raw, maxDimension: backgroundMaxDimension) ?? raw
        await MainActor.run {
            // Preserve current opacity if user is replacing an existing image,
            // otherwise default to fully opaque.
            let opacity: Double = {
                if case .image(let existing) = selection { return existing.opacity }
                return 1.0
            }()
            selection = .image(MockNote.ImageBackground(imageData: downscaled, opacity: opacity))
            // Auto-launch the crop sheet on a fresh pick so the user lands
            // straight in the framing decision (Apple Notes / Notion pattern).
            // Cancel from the crop keeps the uncropped picked photo as-is.
            cropState = PhotoCropState(data: downscaled)
        }
    }

    // MARK: - Color section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                Segmented(
                    options: palettes.map { palette in
                        SegmentedOption(id: palette.id, title: palette.name)
                    },
                    selection: $activePaletteId
                )
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 14)
            swatchGrid
                .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var swatchGrid: some View {
        if let palette = palettes.first(where: { $0.id == activePaletteId }) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: 12)],
                spacing: 12
            ) {
                ForEach(palette.swatches) { swatch in
                    swatchTile(swatch)
                }
            }
            .padding(.horizontal, 20)
            // Breathing room at the bottom so the last grid row doesn't
            // sit flush against the home-indicator zone in the sheet.
            .padding(.bottom, 32)
        }
    }

    private func swatchTile(_ swatch: Swatch) -> some View {
        let isSelected: Bool = {
            if case .color(let id) = selection { return id == swatch.id }
            return false
        }()
        return Button {
            selection = .color(swatchId: swatch.id)
            // Selecting a color clears any prior photo selection state in
            // the picker (the data is already replaced via `selection`).
            photoPickerItem = nil
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(swatch.color())
                        .frame(height: 56)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected ? Color.DS.ink : Color.DS.border1,
                            lineWidth: isSelected ? 2 : 1
                        )
                        .frame(height: 56)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.DS.ink)
                    }
                }
                Text(swatch.name)
                    .font(.DS.sans(size: 11, weight: .medium))
                    .foregroundStyle(Color.DS.fg2)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

private struct BackgroundPickerPreviewHarness: View {
    @State private var selection: MockNote.Background? = nil

    var body: some View {
        BackgroundPickerView(selection: $selection)
    }
}

#Preview("Light") {
    BackgroundPickerPreviewHarness()
}

#Preview("Dark") {
    BackgroundPickerPreviewHarness()
        .preferredColorScheme(.dark)
}
