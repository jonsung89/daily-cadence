import SwiftUI
import PhotosUI

/// Editor flow for a photo or video note (Phase E.3 → E.4.1 → E.5.10).
///
/// **Phase E.4.1** dropped the type picker UI. **Phase E.5.10** finished
/// the job: every saved media note is now auto-tagged `NoteType.media`
/// (was `.general`), so Group / Stack views collect them into their own
/// "Media" section instead of dropping them into the neutral catch-all.
/// If the user wants semantic context with a photo (e.g., "great
/// workout" + image), the canonical pattern is a text note with an
/// attached image — once inline-attachments-in-text-notes ships
/// (deferred follow-up).
///
/// `PhotoCropView` provides the photo crop step. Videos still skip
/// cropping; timeline-trim UX is a separate, larger feature.
///
/// Differs from `NoteEditorScreen` by being single-purpose: the user has
/// already committed to "this is a media note," so we skip the whole
/// styling toolbar / background sheet / rich-text apparatus. Just:
/// - PhotosPicker (photos + videos) — opened from the FAB or via Replace
/// - **Crop step** for photos (`PhotoCropView`) — pan + aspect presets
/// - Optional caption
///
/// Save commits to `TimelineStore.shared` like the text editor does. Cancel
/// dismisses without saving — there's no draft store for media because the
/// asset is the substance and forcing a re-pick on accidental dismiss is
/// less disruptive than re-typing a long message.
struct MediaNoteEditorScreen: View {
    @Environment(\.dismiss) private var dismiss

    /// Initial picker item passed in from the FAB flow (the user already
    /// chose an asset before this sheet opened). May be `nil` if we want
    /// the user to pick inside the sheet — we render the picker upfront
    /// in that case.
    let initialItem: PhotosPickerItem?

    @State private var pickerItem: PhotosPickerItem?
    @State private var payload: MediaPayload?
    /// Owned crop state for image payloads. `nil` for videos (no crop UX
    /// in this phase) and while `payload` is still loading.
    @State private var cropState: PhotoCropState?
    @State private var caption: String = ""
    @State private var isLoading = false
    @State private var importError: String?

    /// Phase F.0.3 — user-overridable timestamp. `nil` until the user
    /// touches the picker; reads default via `defaultOccurredAt` (selected
    /// day + current time-of-day). Lives as @State here rather than in a
    /// shared draft store because media-note editor doesn't persist drafts.
    @State private var occurredAt: Date?

    /// Drives the fullscreen video player from the editor's preview area.
    /// Tapping the play poster sets this true; `MediaViewerScreen` handles
    /// the actual `AVPlayer`. Same surface used by the timeline cards.
    @State private var isVideoPreviewPresented = false

    init(initialItem: PhotosPickerItem? = nil) {
        self.initialItem = initialItem
        self._pickerItem = State(initialValue: initialItem)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewArea
                        .padding(.horizontal, 16)
                    captionField
                        .padding(.horizontal, 20)
                    occurredAtRow
                        .padding(.horizontal, 20)
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.DS.bg1)
            .navigationTitle("New media note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task {
                if let item = initialItem, payload == nil {
                    await importItem(item)
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await importItem(newItem) }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Preview area

    @ViewBuilder
    private var previewArea: some View {
        if isLoading {
            loadingPlaceholder
        } else if let payload {
            switch payload.kind {
            case .image:
                imageCropArea
            case .video:
                videoPreview(payload)
            }
        } else {
            pickerCallout
        }
    }

    private var loadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.DS.bg2)
                .frame(height: 360)
            ProgressView()
        }
        .frame(maxWidth: .infinity)
    }

    /// Image flow: full crop view + Replace/Remove actions.
    @ViewBuilder
    private var imageCropArea: some View {
        if let cropState {
            VStack(spacing: 8) {
                PhotoCropView(state: cropState)
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)

                replaceRemoveRow
                    .padding(.horizontal, 4)
            }
        } else {
            // Defensive — payload exists but cropState init failed (e.g.,
            // the data couldn't decode as a UIImage). Show the picker
            // again so the user can recover.
            pickerCallout
        }
    }

    /// Video flow: read-only preview with tap-to-play + Replace/Remove.
    /// Tapping the poster opens the same `MediaViewerScreen` used from
    /// the timeline — that's where `AVPlayer` runs. Video trim UX is a
    /// separate, larger feature (Phase F.1.1b'); we don't crop video at
    /// all in this phase.
    private func videoPreview(_ payload: MediaPayload) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Color.DS.bg2
                if let posterImage = posterImage(for: payload) {
                    Image(uiImage: posterImage)
                        .resizable()
                        .scaledToFit()
                }
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.DS.ink)
                        .offset(x: 2)
                }
            }
            .aspectRatio(payload.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.DS.border1, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture { isVideoPreviewPresented = true }
            .accessibilityLabel("Play video")
            .accessibilityAddTraits(.isButton)
            .fullScreenCover(isPresented: $isVideoPreviewPresented) {
                MediaViewerScreen(media: payload)
            }

            replaceRemoveRow
                .padding(.horizontal, 4)
        }
    }

    private var replaceRemoveRow: some View {
        HStack(spacing: 12) {
            PhotosPicker(
                selection: $pickerItem,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            ) {
                Label("Replace", systemImage: "photo.on.rectangle")
                    .font(.DS.label)
            }
            Spacer()
            Button(role: .destructive) {
                payload = nil
                cropState = nil
                pickerItem = nil
            } label: {
                Label("Remove", systemImage: "trash")
                    .font(.DS.label)
            }
        }
    }

    private func posterImage(for payload: MediaPayload) -> UIImage? {
        if let poster = payload.posterData, let img = UIImage(data: poster) { return img }
        return payload.data.flatMap(UIImage.init(data:))
    }

    private var pickerCallout: some View {
        PhotosPicker(
            selection: $pickerItem,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        ) {
            VStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.DS.fg2)
                Text("Choose a photo or video")
                    .font(.DS.body)
                    .foregroundStyle(Color.DS.ink)
                Text("From your library")
                    .font(.DS.small)
                    .foregroundStyle(Color.DS.fg2)
                if let importError {
                    Text(importError)
                        .font(.DS.small)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.DS.bg2)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.DS.border1, style: StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Caption

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Caption")
                .font(.DS.label)
                .foregroundStyle(Color.DS.fg2)
            TextField("Optional", text: $caption, axis: .vertical)
                .font(.DS.sans(size: 16, weight: .regular))
                .foregroundStyle(Color.DS.ink)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.DS.bg2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.DS.border1, lineWidth: 1)
                )
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
                .disabled(payload == nil)
        }
    }

    // MARK: - Actions

    private func importItem(_ item: PhotosPickerItem) async {
        await MainActor.run {
            isLoading = true
            importError = nil
        }
        defer {
            Task { @MainActor in isLoading = false }
        }
        do {
            let payload = try await MediaImporter.makePayload(from: item)
            await MainActor.run {
                self.payload = payload
                self.cropState = payload.kind == .image
                    ? payload.data.flatMap(PhotoCropState.init(data:))
                    : nil
            }
        } catch let MediaImporter.ImportError.videoTooLong(seconds) {
            // Phase F.1.1b — surface the 60s cap clearly. F.1.1b' will
            // replace this rejection with a trim sheet that lets the
            // user pick a 60s window from the longer video.
            await MainActor.run {
                let len = Int(seconds.rounded())
                self.importError = "That video is \(len) seconds long. Videos must be 60 seconds or shorter for now — a trim tool is coming soon."
                // Drop the picked item so the empty-state picker shows again.
                self.pickerItem = nil
            }
        } catch {
            await MainActor.run {
                self.importError = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't load that file. Try another one."
            }
        }
    }

    private func save() {
        guard var payload else { return }

        // For image notes, commit the user's crop choices into a fresh
        // MediaPayload before saving. Falls back to the original payload
        // when the crop math fails or the source was a video. Crop only
        // runs in the editor flow where `payload.data` is non-nil
        // (freshly imported), so the cropState bind site already filtered
        // for that.
        if payload.kind == .image, let cropState,
           let result = cropState.commitCrop() {
            payload = MediaPayload(
                kind: .image,
                data: result.data,
                posterData: nil,
                aspectRatio: result.aspectRatio,
                caption: payload.caption
            )
        }

        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalPayload = MediaPayload(
            kind: payload.kind,
            data: payload.data,
            posterData: payload.posterData,
            aspectRatio: payload.aspectRatio,
            caption: trimmedCaption.isEmpty ? nil : trimmedCaption
        )
        let note = MockNote(
            occurredAt: occurredAt ?? defaultOccurredAt,
            type: .media,  // Phase E.5.10 — media notes auto-tag as Media
            content: .media(finalPayload)
        )
        TimelineStore.shared.add(note)
        dismiss()
    }

    /// "Selected day, current time-of-day" — the picker's default.
    private var defaultOccurredAt: Date {
        NoteEditorScreen.combine(
            day: TimelineStore.shared.selectedDate,
            timeOfDay: .now
        )
    }

    /// Date+time row at the bottom of the editor. Same pattern as
    /// `NoteEditorScreen.occurredAtRow` so the two editors stay
    /// visually consistent.
    private var occurredAtRow: some View {
        HStack(spacing: 10) {
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
                    get: { occurredAt ?? defaultOccurredAt },
                    set: { occurredAt = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
    }
}

// MARK: - Previews

#Preview("Empty, light") {
    MediaNoteEditorScreen()
}

#Preview("Empty, dark") {
    MediaNoteEditorScreen()
        .preferredColorScheme(.dark)
}
