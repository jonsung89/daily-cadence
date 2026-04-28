import SwiftUI

/// Renders an inline media block (`TextBlock.media`) inside a card or
/// editor (Phase E.5.18). Used by both `KeepCard` and `NoteCard` so the
/// visual treatment stays identical across Board and Timeline contexts.
///
/// **Sizing.** Uses a `GeometryReader` to measure the available content
/// width, then applies `size.widthFraction` to determine the rendered
/// width. Height is derived from the asset's clamped aspect ratio
/// (`MediaPayload.aspectRatio`). The block is centered for Small /
/// Medium and full-width for Large per `size.horizontalAlignment`.
///
/// **Interaction.** The whole image is a tap target — tapping opens the
/// asset in `MediaViewerScreen` (full-screen viewer with pinch-zoom for
/// images, AVPlayer for videos). Videos display a `play.fill` glyph in
/// a `.ultraThinMaterial` circle as the press affordance.
struct InlineMediaBlockView: View {
    let payload: MediaPayload
    let size: MediaBlockSize
    /// Corner radius applied to the rendered media. `KeepCard` uses 8pt
    /// (matches the card's inner content rhythm); `NoteCard` uses 10pt
    /// for slightly softer Timeline feel.
    var cornerRadius: CGFloat = 8
    /// When true (default), tapping the media opens
    /// `MediaViewerScreen` full-screen — the read-only card behavior.
    /// Set to `false` in editor contexts so a parent `Menu` wrapper can
    /// take the tap (resize / remove).
    var isInteractive: Bool = true
    /// Phase F.1.1b'.zoom — when both `mediaTapHandler` and `blockId`
    /// are set, taps route through the parent's matched-geo zoom (same
    /// pipeline `KeepCard.mediaScaffold` uses for standalone-media
    /// notes). When unset, the legacy `.fullScreenCover` slide-up
    /// fallback handles preview surfaces and the editor's strip.
    var mediaTapHandler: MediaTapHandler? = nil
    var blockId: UUID? = nil

    @State private var isViewerPresented = false

    /// Phase F.1.2.inlinevideo — first-tap-to-play state for inline
    /// video blocks. Same lifecycle as the standalone-media variants in
    /// NoteCard / KeepCard.
    @State private var isInlinePlaying = false
    @State private var inlineVideoURL: URL?
    @State private var inlineVideoIsTempFile = false

    var body: some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width
            let renderWidth = contentWidth * size.widthFraction
            let renderHeight = renderWidth / payload.aspectRatio

            HStack {
                if size.horizontalAlignment == .center {
                    Spacer(minLength: 0)
                }
                ZStack {
                    Color.DS.bg2
                    if let posterImage = inlinePosterImage() {
                        // Fast path — inline bytes available (just-imported
                        // payload in the editor's strip, or a not-yet-uploaded
                        // session-only note). Renders synchronously.
                        Image(uiImage: posterImage)
                            .resizable()
                            .scaledToFill()
                    } else if payload.ref != nil || payload.posterRef != nil || payload.thumbnailRef != nil {
                        // Fetched-from-server media — bytes resolve via
                        // `MediaResolver` (signed URL + URLCache). Without
                        // this branch, a reloaded note's inline-block
                        // renders an empty white box.
                        ResolvedMediaPoster(payload: payload)
                    }
                    // Phase F.1.2.inlinevideo — same first-tap-to-play
                    // pattern as the standalone-media cards. Plays once
                    // muted; tap during playback opens fullscreen with
                    // audio; resets to poster on completion.
                    if payload.kind == .video, isInlinePlaying, let url = inlineVideoURL {
                        InlineVideoPlayer(url: url, onEnded: stopInlineVideo)
                    }
                    if payload.kind == .video, !isInlinePlaying {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 36, height: 36)
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.DS.ink)
                                .offset(x: 1)
                        }
                    }
                }
                .frame(width: renderWidth, height: renderHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.DS.border1, lineWidth: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .onTapGesture {
                    if isInteractive { handleTap() }
                }
                .onDisappear { stopInlineVideo() }
                // Publish this block's frame to the matched-geo source-frame
                // map and gate opacity during the open/close so the viewer's
                // image renders in this slot, not over it. Falls through to
                // the identity branch when no handler is provided (preview /
                // editor surfaces).
                .modifier(MatchedGeometryModifier(
                    handler: mediaTapHandler,
                    id: blockId ?? UUID()
                ))
                if size.horizontalAlignment == .center {
                    Spacer(minLength: 0)
                }
            }
            .frame(width: contentWidth, height: renderHeight)
        }
        // The GeometryReader takes only the height of its content via
        // a fixed-size child below. We compute height from the size
        // preset + aspect ratio in the layer above; here we simply need
        // the GeometryReader to allocate the right outer height.
        .aspectRatio(aspectRatioForLayout, contentMode: .fit)
        .fullScreenCover(isPresented: $isViewerPresented) {
            // Legacy slide-up fallback — used only when no
            // `mediaTapHandler` is provided (previews, editor strip).
            MediaViewerScreen(media: payload)
        }
        .accessibilityLabel(payload.kind == .video ? "Play video" : "Open photo")
        .accessibilityAddTraits(.isButton)
    }

    /// The aspect ratio the outer container needs so the GeometryReader
    /// allocates the right vertical space. For Small / Medium the height
    /// is determined by the *rendered* width (a fraction of the content),
    /// not the full content width — so we scale the aspect ratio
    /// accordingly.
    private var aspectRatioForLayout: CGFloat {
        // height = (contentWidth * widthFraction) / payloadAspect
        // outer container has `contentWidth` width and that height,
        // so its aspect ratio = contentWidth / height
        //                     = contentWidth / (contentWidth * widthFraction / payloadAspect)
        //                     = payloadAspect / widthFraction
        payload.aspectRatio / size.widthFraction
    }

    /// Routes a tap to the parent's zoom-transition handler when one is
    /// provided; otherwise falls through to the legacy fullScreenCover.
    ///
    /// Phase F.1.2.inlinevideo — for video media, first tap starts inline
    /// muted playback; subsequent tap opens fullscreen.
    private func handleTap() {
        if payload.kind == .video, !isInlinePlaying {
            startInlineVideo()
            return
        }
        // Stop inline before fullscreen so we don't have two players
        // running against the same source.
        stopInlineVideo()
        if let handler = mediaTapHandler, let blockId {
            handler.onTap(payload, blockId)
        } else {
            isViewerPresented = true
        }
    }

    private func startInlineVideo() {
        Task {
            guard let resolved = await InlineVideoPlayer.resolveURL(for: payload) else { return }
            await MainActor.run {
                inlineVideoURL = resolved.url
                inlineVideoIsTempFile = resolved.isTempFile
                isInlinePlaying = true
            }
        }
    }

    private func stopInlineVideo() {
        if inlineVideoIsTempFile, let url = inlineVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        inlineVideoURL = nil
        inlineVideoIsTempFile = false
        isInlinePlaying = false
    }

    /// Synchronous inline-bytes lookup — kind-aware, mirrors
    /// `MediaResolver.posterBytes(for:)`'s preference chain so the inline
    /// fast path matches the resolved fallback. Returns `nil` when no
    /// inline bytes are present (fetched-from-server media); the caller
    /// falls back to `ResolvedMediaPoster` in that case.
    private func inlinePosterImage() -> UIImage? {
        switch payload.kind {
        case .image:
            // F.1.1b dual-size: prefer the small HEIC thumbnail (~80 KB)
            // over the full asset (~400 KB).
            if let thumb = payload.thumbnailData, let img = UIImage(data: thumb) {
                return img
            }
            return payload.data.flatMap(UIImage.init(data:))
        case .video:
            return payload.posterData.flatMap(UIImage.init(data:))
        }
    }
}
