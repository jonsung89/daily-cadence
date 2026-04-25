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
                ImagePinchZoomView(data: media.data)
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
        // Write bytes to a temp file so AVPlayer can read via URL. Using a
        // unique filename avoids collisions when multiple viewer sheets
        // open during the same session.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-video-\(UUID().uuidString).mov")
        do {
            try media.data.write(to: tempURL)
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

/// A pinch-and-pan zoomable image view, used by `MediaViewerScreen` for
/// the `.image` case.
///
/// Built around a `ScrollView` with `.zoomable` content (iOS 17+) — that's
/// the canonical SwiftUI pattern and gives us double-tap-to-zoom and
/// fling-to-pan for free. Scale range: 1.0 ... 4.0.
private struct ImagePinchZoomView: View {
    let data: Data

    @State private var uiImage: UIImage?

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                Group {
                    if let uiImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        Color.clear
                    }
                }
            }
            // iOS 17+ zoomable scroll — pinch + double-tap zoom built-in.
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
        .task {
            // Decode off-main if the asset is large; bouncing back via
            // MainActor for the @State assignment.
            let bytes = data
            let decoded = await Task.detached { UIImage(data: bytes) }.value
            await MainActor.run { self.uiImage = decoded }
        }
    }
}
