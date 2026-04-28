import SwiftUI

/// Full-screen viewer for a `MediaPayload` — a shared envelope that
/// handles the matched-geometry zoom open/close, drag-down dismiss, and
/// chrome (close button, caption) for both image and video. The actual
/// content (image with pinch-zoom, video with AVKit chrome + drag-coexist)
/// lives in `ImageMediaContent` / `VideoMediaContent`. Both content
/// variants write their drag-dismiss state into bindings owned here, so
/// the visual translate + scale effect is applied uniformly at this
/// level regardless of media kind.
///
/// **Phase F.1.1b'.zoom — manual matched-geometry overlay.** Rather than
/// pushing onto a `NavigationStack` (whose interactive dismiss snapshots
/// the destination and hides our live state-driven visuals), this view
/// is rendered as a ZStack overlay on top of the active screen. The
/// underlying timeline keeps rendering, so the backdrop fade during a
/// drag-dismiss reveals the actual cards — same trick as Apple Photos.
///
/// `RootView` interpolates `openProgress` from 0 (image at source-card
/// frame) to 1 (image at fullscreen-fitted frame) on present, and back
/// to 0 on dismiss. We compute the current frame each render via
/// `lerp(sourceFrame → fitFrame)` and apply it to the content with
/// `.frame` + `.position`.
struct MediaViewerScreen: View {
    let media: MediaPayload
    /// Source card's image-area frame in global coords, captured at
    /// tap time. `nil` for the fallback `.fullScreenCover` path
    /// (previews / non-Timeline surfaces), in which case the image
    /// just renders at fullscreen with no zoom interpolation.
    var sourceFrame: CGRect? = nil
    /// 0 = content at `sourceFrame`, 1 = content at fullscreen-fitted
    /// frame. RootView animates this with `.smooth(duration: 0.5)` on
    /// present/dismiss.
    var openProgress: CGFloat = 1
    /// Called when the user taps close OR completes a drag-dismiss.
    /// Defaults to `dismiss()` so the fallback `.fullScreenCover` path
    /// still works without an explicit handler.
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    /// Drag-dismiss state — owned here so both image and video content
    /// share the same visual effect. The content writes into these
    /// bindings; the viewer reads them to translate the framed content
    /// (`.offset(dismissOffset)`), scale it (`.scaleEffect(dismissScale)`),
    /// and fade the backdrop + chrome (`(1 - dismissProgress)`).
    @State private var dismissOffset: CGSize = .zero
    @State private var dismissProgress: CGFloat = 0
    @State private var dismissScale: CGFloat = 1.0

    /// Flips to `true` synchronously when `performDismiss` runs (X button,
    /// drag-commit, or fallback). `VideoMediaContent` observes this to
    /// pause the player so audio doesn't bleed through the ~510 ms close
    /// animation. Image content ignores it.
    @State private var isDismissing: Bool = false

    /// Resolves to the explicit `onDismiss` if the parent provided one
    /// (overlay path), otherwise falls back to the environment dismiss
    /// (fullScreenCover path).
    private func performDismiss() {
        isDismissing = true
        if let onDismiss { onDismiss() } else { dismiss() }
    }

    var body: some View {
        GeometryReader { geo in
            let viewerGlobal = geo.frame(in: .global)
            let viewerSize = geo.size
            let fitFrame = aspectFitFrame(in: viewerSize)
            let imageFrame: CGRect = {
                guard let sourceFrame else { return fitFrame }
                let localSource = CGRect(
                    x: sourceFrame.minX - viewerGlobal.minX,
                    y: sourceFrame.minY - viewerGlobal.minY,
                    width: sourceFrame.width,
                    height: sourceFrame.height
                )
                return lerp(from: localSource, to: fitFrame, t: openProgress)
            }()

            ZStack {
                // Backdrop: openProgress fades it in/out; dismissProgress
                // fades it during drag-dismiss. Combined formula keeps
                // the timeline visible through both phases.
                Color.black
                    .opacity(openProgress * (1.0 - dismissProgress))
                    .ignoresSafeArea()

                content
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)
                    // Constant 10pt matches the source card's corner radius
                    // so the close-handoff has no corner-shape pop. The
                    // slight rounding at fullscreen edges is intentional
                    // and matches Photos.
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    // Drag-dismiss visual effect — applied here so both
                    // image and video share it. The content writes to the
                    // bindings via its own gesture; this just consumes them.
                    .scaleEffect(dismissScale)
                    .offset(dismissOffset)

                chrome
                    .opacity(openProgress * (1.0 - dismissProgress))
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch media.kind {
        case .image:
            if let data = media.data {
                ImageMediaContent(
                    data: data,
                    thumbnailData: media.thumbnailData,
                    dismissOffset: $dismissOffset,
                    dismissProgress: $dismissProgress,
                    dismissScale: $dismissScale,
                    onDismissCommitted: performDismiss
                )
            } else {
                // Phase F.1.1: fetched-from-server media. Resolves bytes
                // via `MediaResolver`.
                ResolvedFullscreenImage(
                    payload: media,
                    dismissOffset: $dismissOffset,
                    dismissProgress: $dismissProgress,
                    dismissScale: $dismissScale,
                    onDismissCommitted: performDismiss
                )
            }
        case .video:
            VideoMediaContent(
                media: media,
                dismissOffset: $dismissOffset,
                dismissProgress: $dismissProgress,
                dismissScale: $dismissScale,
                isDismissing: isDismissing,
                onDismissCommitted: performDismiss
            )
        }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    performDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
                .accessibilityLabel("Close")
            }
            Spacer()
            bottomChrome
        }
    }

    /// Bottom chrome — caption (centered) and capture date (lower-left)
    /// share a single gradient backdrop. Renders nothing when neither is
    /// present so a metadata-less photo gets a clean unobstructed bottom.
    @ViewBuilder
    private var bottomChrome: some View {
        let caption = media.caption?.isEmpty == false ? media.caption : nil
        let dateText = media.capturedAt.map { $0.formatted(date: .abbreviated, time: .shortened) }

        if caption != nil || dateText != nil {
            VStack(spacing: 6) {
                if let caption {
                    Text(caption)
                        .font(.DS.sans(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                if let dateText {
                    Text(dateText)
                        .font(.DS.sans(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Captured \(dateText)")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .background {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }

    /// Aspect-fitted rect centered in the available viewer size. The
    /// source-card frame and this fit frame share the same aspect ratio
    /// (cards lay out at `media.aspectRatio` too) so the lerp between
    /// them is a clean uniform scale — no shifting mid-zoom.
    private func aspectFitFrame(in size: CGSize) -> CGRect {
        let imageAspect = max(media.aspectRatio, 0.001)
        let widthIfFitWidth = size.width
        let heightIfFitWidth = widthIfFitWidth / imageAspect
        if heightIfFitWidth <= size.height {
            return CGRect(
                x: 0,
                y: (size.height - heightIfFitWidth) / 2,
                width: widthIfFitWidth,
                height: heightIfFitWidth
            )
        } else {
            let heightIfFitHeight = size.height
            let widthIfFitHeight = heightIfFitHeight * imageAspect
            return CGRect(
                x: (size.width - widthIfFitHeight) / 2,
                y: 0,
                width: widthIfFitHeight,
                height: heightIfFitHeight
            )
        }
    }

    private func lerp(from: CGRect, to: CGRect, t: CGFloat) -> CGRect {
        let clampedT = max(0, min(1, t))
        return CGRect(
            x: from.minX + (to.minX - from.minX) * clampedT,
            y: from.minY + (to.minY - from.minY) * clampedT,
            width: from.width + (to.width - from.width) * clampedT,
            height: from.height + (to.height - from.height) * clampedT
        )
    }
}
