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
/// hands off to `ImagePinchZoomView` for Apple Photos-style pinch +
/// double-tap zoom.
struct ResolvedFullscreenImage: View {
    let payload: MediaPayload

    @State private var data: Data?

    var body: some View {
        Group {
            if let data {
                ImagePinchZoomView(data: data)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: payload.ref?.path ?? "") {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        guard data == nil else { return }
        do {
            data = try await MediaResolver.shared.bytes(for: payload)
        } catch {
            // Silent fail — spinner stays visible. F+ can surface a retry.
        }
    }
}
