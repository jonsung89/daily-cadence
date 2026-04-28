import SwiftUI
import AVFoundation

/// Phase F.1.2.inlinevideo — minimal video player for **in-card** muted
/// playback. Distinct from `VideoMediaContent` (the fullscreen viewer)
/// — no AVKit chrome, no drag-dismiss, no scrubber. Just an
/// `AVPlayerLayer` rendering muted video that plays once and fires
/// `onEnded` when finished.
///
/// **Lifecycle.** The card owns the playback state (`isInlinePlaying`)
/// and renders this view only while it should be active. The
/// `dismantleUIView` hook pauses the player and removes the
/// `AVPlayerItemDidPlayToEndTime` observer, so cleanup is automatic
/// when SwiftUI removes this view (the card setting `isInlinePlaying =
/// false` after `onEnded`, after fullscreen open, or on
/// `.onDisappear`).
///
/// **No looping.** Per Jon's spec, plays once then surrenders to the
/// poster. The card resets to its initial state (poster + play button)
/// on `onEnded`.
///
/// **`videoGravity = .resizeAspectFill`** so the video fills the card
/// frame the same way the poster did — no letterboxing inside the
/// card. Outer `.clipShape` on the card frame keeps the corners
/// rounded.
struct InlineVideoPlayer: UIViewRepresentable {
    let url: URL
    let onEnded: () -> Void

    func makeUIView(context: Context) -> InlineVideoPlayerView {
        let view = InlineVideoPlayerView()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        // `.pause` so the player stops at the last frame instead of
        // resetting; we tear down via `dismantleUIView` once the card
        // hides this view in response to `onEnded`.
        player.actionAtItemEnd = .pause
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill

        context.coordinator.attach(player: player, item: item, onEnded: onEnded)
        player.play()
        return view
    }

    func updateUIView(_ uiView: InlineVideoPlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: InlineVideoPlayerView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var player: AVPlayer?
        private var endObserver: NSObjectProtocol?

        func attach(player: AVPlayer, item: AVPlayerItem, onEnded: @escaping () -> Void) {
            self.player = player
            self.endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in onEnded() }
        }

        func detach() {
            player?.pause()
            if let observer = endObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            endObserver = nil
            player = nil
        }
    }
}

/// Backing UIView whose backing layer IS an `AVPlayerLayer` — avoids
/// the manual sublayer-frame-sync that a plain UIView wrapper would
/// require. UIKit auto-resizes the layer with the view.
final class InlineVideoPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

// MARK: - URL resolution

extension InlineVideoPlayer {
    /// Resolved playable source. `isTempFile` tells the caller whether
    /// to delete the URL on cleanup (true for inline-bytes payloads
    /// written to disk; false for streaming signed URLs that the OS
    /// manages).
    struct Source {
        let url: URL
        let isTempFile: Bool
    }

    /// Resolves a `MediaPayload` to a playable URL. Prefers a streaming
    /// signed URL when the payload has a `ref` (saves writing bytes to
    /// disk); falls back to a temp file from inline `data` for newly
    /// imported clips that haven't uploaded yet. Returns nil on failure
    /// (network error, missing both `ref` and `data`).
    static func resolveURL(for payload: MediaPayload) async -> Source? {
        if let ref = payload.ref {
            if let url = try? await MediaResolver.shared.signedURL(for: ref) {
                return Source(url: url, isTempFile: false)
            }
        }
        guard let data = payload.data else { return nil }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-inline-video-\(UUID().uuidString).mov")
        do {
            try data.write(to: tempURL)
            return Source(url: tempURL, isTempFile: true)
        } catch {
            return nil
        }
    }
}
