import SwiftUI
import AVKit
import AVFoundation

/// Apple Photos–style fullscreen video content. Shares the outer
/// `MediaViewerScreen` envelope (matched-geo zoom, corner clip, chrome,
/// drag-dismiss visual effect) with `ImageMediaContent`; what's specific
/// to video lives here:
///
/// 1. **Poster handoff during zoom.** The same poster image the source
///    card was rendering is sync-decoded in `init` and shown immediately
///    so the open-zoom transition has visible content from frame one. A
///    crossfade swaps in the live `AVPlayerViewController` once
///    `currentItem.status == .readyToPlay`, avoiding the black-blink an
///    `AVPlayer` shows while the asset loads.
///
/// 2. **AVKit-coexisting drag-dismiss.** A `UIPanGestureRecognizer`
///    attached to the player view recognizes simultaneously with all of
///    AVKit's internal gestures (scrubber, tap-to-toggle-controls), but
///    only **begins** when the initial velocity is vertical-dominant and
///    downward. Horizontal scrubs never claim the recognizer; vertical
///    drags never reach the scrubber. Same trick Photos uses.
///
/// 3. **Auto-pause on dismiss.** `isDismissing` flips when the viewer's
///    `performDismiss` runs (X button OR drag-commit OR fallback dismiss).
///    `.onChange` pauses the player synchronously so audio doesn't bleed
///    through the close animation.
struct VideoMediaContent: View {
    let media: MediaPayload
    @Binding var dismissOffset: CGSize
    @Binding var dismissProgress: CGFloat
    @Binding var dismissScale: CGFloat
    /// Flipped to `true` by `MediaViewerScreen.performDismiss` (X button,
    /// drag-commit, or fallback). Pauses the player synchronously so
    /// audio doesn't bleed through the close animation.
    let isDismissing: Bool
    let onDismissCommitted: () -> Void

    @State private var posterImage: UIImage?
    @State private var player: AVPlayer?
    @State private var playerReady: Bool = false
    @State private var videoURL: URL?

    init(
        media: MediaPayload,
        dismissOffset: Binding<CGSize>,
        dismissProgress: Binding<CGFloat>,
        dismissScale: Binding<CGFloat>,
        isDismissing: Bool,
        onDismissCommitted: @escaping () -> Void
    ) {
        self.media = media
        self._dismissOffset = dismissOffset
        self._dismissProgress = dismissProgress
        self._dismissScale = dismissScale
        self.isDismissing = isDismissing
        self.onDismissCommitted = onDismissCommitted
        // Sync-decode the poster in init so the very first zoom frame
        // already paints — same trick `ImageMediaContent` uses with the
        // image thumbnail. Falls back to nil for fetched videos whose
        // `posterData` is empty (`posterRef` resolves async; we accept a
        // brief black blink in that path).
        if let posterData = media.posterData, let img = UIImage(data: posterData) {
            self._posterImage = State(initialValue: img)
        } else {
            self._posterImage = State(initialValue: nil)
        }
    }

    var body: some View {
        ZStack {
            // Poster — visible until the player has its first frame.
            // `.scaledToFit` matches the aspect-fitted frame the viewer
            // computes from `media.aspectRatio`, so the poster's bounds
            // align with both the source-card image and the eventual
            // video frame; the crossfade is invisible.
            if let posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFit()
                    .opacity(playerReady ? 0 : 1)
            } else {
                Color.black
            }

            if let player {
                PlayerViewControllerRepresentable(
                    player: player,
                    dismissOffset: $dismissOffset,
                    dismissProgress: $dismissProgress,
                    dismissScale: $dismissScale,
                    onDismissCommitted: onDismissCommitted
                )
                .opacity(playerReady ? 1 : 0)
            }
        }
        .task { await prepare() }
        .onChange(of: isDismissing) { _, newValue in
            if newValue { player?.pause() }
        }
        .onDisappear { teardown() }
    }

    private func prepare() async {
        // 1. Build the player (signed URL for fetched videos, temp file
        //    for newly-imported inline bytes).
        if player == nil {
            await buildPlayer()
        }
        guard let player else { return }
        // 2. Wait for the first frame to be decodable, then crossfade.
        //    Polling beats KVO here — the wait is typically 100–300 ms
        //    and the loop exits cleanly when the view goes away.
        while !Task.isCancelled {
            if player.currentItem?.status == .readyToPlay {
                playerReady = true
                player.play()
                return
            }
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    private func buildPlayer() async {
        // Phase F.1.1: prefer streaming via signed URL when we have a ref —
        // saves writing the full video to a temp file. Falls back to the
        // inline-bytes path for newly-imported media that hasn't finished
        // its background upload.
        if let ref = media.ref {
            do {
                let url = try await MediaResolver.shared.signedURL(for: ref)
                await MainActor.run { self.player = AVPlayer(url: url) }
                return
            } catch {
                // Fall through to inline-bytes path.
            }
        }
        guard let data = media.data else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-video-\(UUID().uuidString).mov")
        do {
            try data.write(to: tempURL)
            await MainActor.run {
                self.videoURL = tempURL
                self.player = AVPlayer(url: tempURL)
            }
        } catch {
            // Silent fail — the poster stays visible. Real apps would
            // surface a toast or retry button; not in scope for F.1.1.
        }
    }

    private func teardown() {
        player?.pause()
        if let url = videoURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - AVPlayerViewController bridge with vertical-only pan recognizer

/// Wraps `AVPlayerViewController` so we can attach a `UIPanGestureRecognizer`
/// that coexists with AVKit's internal gestures. The recognizer only
/// begins on vertical-dominant downward motion; horizontal scrubs and
/// taps fall through to AVKit untouched.
private struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    @Binding var dismissOffset: CGSize
    @Binding var dismissProgress: CGFloat
    @Binding var dismissScale: CGFloat
    let onDismissCommitted: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.videoGravity = .resizeAspect
        vc.allowsPictureInPicturePlayback = false
        vc.showsPlaybackControls = true
        vc.updatesNowPlayingInfoCenter = false

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        // We do not want to swallow touches — AVKit needs to keep
        // receiving them for tap-to-toggle and scrub handling.
        pan.cancelsTouchesInView = false
        vc.view.addGestureRecognizer(pan)

        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // Keep the coordinator's binding accessors fresh — SwiftUI may
        // produce a new representable instance per render and the
        // coordinator's stored `parent` would otherwise capture stale
        // bindings.
        context.coordinator.parent = self
        if vc.player !== player {
            vc.player = player
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PlayerViewControllerRepresentable

        // Mirror the thresholds in `ImageMediaContent` so the dismiss
        // feel is identical across image and video.
        private let dismissProgressDenominator: CGFloat = 200
        private let dismissTranslationThreshold: CGFloat = 120
        private let dismissVelocityThreshold: CGFloat = 600

        init(parent: PlayerViewControllerRepresentable) {
            self.parent = parent
        }

        // MARK: UIGestureRecognizerDelegate

        /// Coexist with all of AVKit's internal recognizers — we never
        /// want to block scrubber or tap-to-toggle.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        /// Filter at begin time: only claim the gesture if the user's
        /// initial motion is vertical-dominant and downward. AVKit's
        /// horizontal scrubber drag has horizontal-dominant velocity at
        /// this moment and naturally wins.
        func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
            guard let pan = gr as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.y) > abs(v.x) && v.y > 0
        }

        // MARK: Pan action

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            switch gr.state {
            case .changed:
                let translation = gr.translation(in: gr.view)
                guard translation.y >= 0 else { return }
                let progress = min(translation.y / dismissProgressDenominator, 1.0)
                parent.dismissOffset = CGSize(width: translation.x, height: translation.y)
                parent.dismissProgress = progress
                parent.dismissScale = 1.0 - progress * 0.3

            case .ended:
                let translation = gr.translation(in: gr.view)
                let velocity = gr.velocity(in: gr.view)
                if translation.y > dismissTranslationThreshold || velocity.y > dismissVelocityThreshold {
                    withAnimation(.smooth(duration: 0.5)) {
                        parent.dismissOffset = .zero
                        parent.dismissScale = 1.0
                    }
                    parent.onDismissCommitted()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        parent.dismissOffset = .zero
                        parent.dismissProgress = 0
                        parent.dismissScale = 1.0
                    }
                }

            case .cancelled, .failed:
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    parent.dismissOffset = .zero
                    parent.dismissProgress = 0
                    parent.dismissScale = 1.0
                }

            default:
                break
            }
        }
    }
}
