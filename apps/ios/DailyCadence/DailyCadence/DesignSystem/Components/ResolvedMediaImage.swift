import SwiftUI
import UIKit

/// Renders the poster image for a `MediaPayload`. Inline bytes display
/// instantly; refs resolve through `MediaResolver` (signed URL +
/// URLCache layer). While loading shows a soft taupe placeholder.
///
/// Phase F.1.1a — used by `KeepCard` and `NoteCard` media scaffolds when
/// the payload's inline `posterData`/`data` are nil (fetched-from-server
/// media). Cards still try `posterImage(for:)` first for the fast path
/// when bytes are inline; this view is the lazy-fetch fallback.
struct ResolvedMediaPoster: View {
    let payload: MediaPayload

    @State private var image: UIImage?
    @State private var didTryFetch = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Soft taupe placeholder while loading — matches the
                // empty-card surface so the area doesn't read as broken.
                Rectangle()
                    .fill(Color.DS.taupe.opacity(0.4))
            }
        }
        .task(id: payload.ref?.path ?? "") {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        guard !didTryFetch, image == nil else { return }
        didTryFetch = true
        do {
            if let data = try await MediaResolver.shared.posterBytes(for: payload),
               let img = UIImage(data: data) {
                image = img
            }
        } catch {
            // Silent fail — placeholder remains. Real apps surface a
            // toast or retry button; not in scope for F.1.1a.
        }
    }
}

/// Fullscreen image view for fetched media (`MediaViewerScreen` uses this
/// when `media.data` is nil). Pulls bytes via `MediaResolver`, then
/// hands off to `ImageMediaContent` for Apple Photos-style pinch +
/// double-tap zoom + drag-down-to-dismiss.
///
/// Forwards the dismiss bindings up from `MediaViewerScreen` so a
/// fetched image gets the same drag-dismiss behavior as a local one.
struct ResolvedFullscreenImage: View {
    let payload: MediaPayload
    @Binding var dismissOffset: CGSize
    @Binding var dismissProgress: CGFloat
    @Binding var dismissScale: CGFloat
    let onDismissCommitted: () -> Void

    @State private var data: Data?
    /// Pre-fetched thumbnail bytes (~80 KB HEIC). Loaded in parallel
    /// with the full asset so the viewer has *something* to render
    /// during the zoom-in transition — full bytes can take a beat to
    /// arrive over the network. Same trick the inline-data path uses.
    @State private var thumbnailData: Data?

    var body: some View {
        Group {
            if let data {
                ImageMediaContent(
                    data: data,
                    thumbnailData: thumbnailData,
                    dismissOffset: $dismissOffset,
                    dismissProgress: $dismissProgress,
                    dismissScale: $dismissScale,
                    onDismissCommitted: onDismissCommitted
                )
            } else if let thumbnailData {
                // Thumbnail-only first frame while the full asset
                // resolves. Skips the spinner — better UX than a black
                // canvas during the fetch.
                ImageMediaContent(
                    data: thumbnailData,
                    thumbnailData: thumbnailData,
                    dismissOffset: $dismissOffset,
                    dismissProgress: $dismissProgress,
                    dismissScale: $dismissScale,
                    onDismissCommitted: onDismissCommitted
                )
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: payload.ref?.path ?? "") {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        // Kick off both fetches concurrently — thumbnail typically
        // arrives first (smaller + already URLCache-warmed from the
        // card's poster render).
        async let thumb: Data? = {
            do { return try await MediaResolver.shared.posterBytes(for: payload) }
            catch { return nil }
        }()
        async let full: Data? = {
            guard data == nil else { return data }
            do { return try await MediaResolver.shared.bytes(for: payload) }
            catch { return nil }
        }()
        let (t, f) = await (thumb, full)
        if let t, thumbnailData == nil { thumbnailData = t }
        if let f { data = f }
    }
}
