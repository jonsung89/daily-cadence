import SwiftUI
import AVKit
import AVFoundation

/// Full-screen viewer for a `MediaPayload` — image with pinch-zoom, or video
/// with `AVKit`'s standard player UI.
///
/// Presented via `.fullScreenCover` from `KeepCard` and `NoteCard` when a
/// media note is tapped. The viewer is intentionally minimal — black
/// backdrop, single Done button (top-trailing), no chrome — so the content
/// gets the whole canvas.
///
/// **Video temp-file dance.** `AVPlayer` reads from a `URL`, not raw bytes.
/// We write the payload's `Data` to a temp file on appear and tear it down
/// on dismiss. For the in-memory MVP that's fine; once Supabase Storage
/// lands the URL points to a remote object instead.
struct MediaViewerScreen: View {
    let media: MediaPayload
    @Environment(\.dismiss) private var dismiss

    @State private var videoURL: URL? = nil
    @State private var player: AVPlayer? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch media.kind {
            case .image:
                if let data = media.data {
                    ImagePinchZoomView(data: data)
                } else {
                    // Phase F.1.1: fetched-from-server media. Resolves bytes
                    // via `MediaResolver` against `media.ref`.
                    ResolvedFullscreenImage(payload: media)
                }
            case .video:
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                        .onAppear { player.play() }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        player?.pause()
                        dismiss()
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
                if let caption = media.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.DS.sans(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
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
        }
        .statusBarHidden(true)
        .task { await prepareVideoIfNeeded() }
        .onDisappear { teardownVideo() }
    }

    private func prepareVideoIfNeeded() async {
        guard media.kind == .video else { return }
        // Phase F.1.1: prefer streaming via signed URL when we have a ref —
        // saves writing the full video to a temp file. Falls back to the
        // inline bytes path for newly-imported media that hasn't uploaded
        // yet (its `ref` is nil until the background upload completes).
        if let ref = media.ref {
            do {
                let url = try await MediaResolver.shared.signedURL(for: ref)
                await MainActor.run { self.player = AVPlayer(url: url) }
                return
            } catch {
                // Fall through to inline-bytes path if signed URL failed.
            }
        }
        guard let data = media.data else { return }
        // Write bytes to a temp file so AVPlayer can read via URL. Using a
        // unique filename avoids collisions when multiple viewer sheets
        // open during the same session.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-video-\(UUID().uuidString).mov")
        do {
            try data.write(to: tempURL)
            await MainActor.run {
                self.videoURL = tempURL
                self.player = AVPlayer(url: tempURL)
            }
        } catch {
            // Silent fail — the ProgressView stays visible. Phase F can
            // surface an error toast if this turns out to bite real users.
        }
    }

    private func teardownVideo() {
        player?.pause()
        if let url = videoURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Pinch-zoom image

/// Apple Photos–style pinch-and-pan fullscreen image. Image fits the
/// device width by default; pinch to zoom up to 5× ; double-tap toggles
/// between fit and 2.5×; pan when zoomed.
///
/// Phase F.1.1a fix: the prior implementation claimed iOS 17 `.zoomable`
/// scroll but actually just used a regular ScrollView, which rendered
/// images at full pixel size — a 4032×3024 photo became a 4032pt-wide
/// scrollable area on a 393pt screen. This is a real `MagnifyGesture` +
/// `DragGesture` rewrite with the standard double-tap toggle.
struct ImagePinchZoomView: View {
    let data: Data

    @State private var uiImage: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            Group {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnificationGesture)
                        .simultaneousGesture(panGesture)
                        .onTapGesture(count: 2) { handleDoubleTap() }
                } else {
                    Color.clear
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .task {
            // Decode off-main for large assets; bounce back to main for @State.
            let bytes = data
            let decoded = await Task.detached { UIImage(data: bytes) }.value
            await MainActor.run { self.uiImage = decoded }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = clampedScale(lastScale * value.magnification)
            }
            .onEnded { _ in
                if scale < minScale {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = minScale
                        offset = .zero
                        lastOffset = .zero
                    }
                }
                lastScale = scale
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func handleDoubleTap() {
        withAnimation(.easeOut(duration: 0.22)) {
            if scale > minScale {
                scale = minScale
                lastScale = minScale
                offset = .zero
                lastOffset = .zero
            } else {
                scale = doubleTapScale
                lastScale = doubleTapScale
            }
        }
    }

    private func clampedScale(_ raw: CGFloat) -> CGFloat {
        // Allow over-pinch slightly below 1× during gesture for a rubber-band
        // feel — onEnded snaps back. Clamp the upper bound hard.
        min(max(raw, minScale * 0.85), maxScale)
    }
}
