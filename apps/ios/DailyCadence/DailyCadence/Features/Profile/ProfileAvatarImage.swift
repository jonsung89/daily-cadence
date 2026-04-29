import SwiftUI

/// Loads a private profile photo from Storage by its bucket-relative
/// path and renders it. Backed by `ProfileImageCache` so a hit is
/// instant — only the first render per path per session pays the
/// network cost (sign URL + download bytes). Cache misses fall
/// through to a fetch + decode + cache pipeline.
///
/// Renders nothing while loading or on failure; the caller layers a
/// fallback (initials, plant, etc.) underneath via ZStack.
struct ProfileAvatarImage: View {
    let path: String

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: path) { await load() }
    }

    private func load() async {
        // Fast path: decoded image in memory. Settings → away →
        // back to Settings hits this every time after the first
        // load, so the avatar renders without flash.
        if let cached = ProfileImageCache.shared.image(for: path) {
            image = cached
            return
        }
        // Cold path: signed URL (cached within TTL) → bytes →
        // decode → cache. The bytes themselves also land in
        // `URLCache.shared` so a second app launch within the
        // signed URL's TTL serves from disk.
        do {
            let url = try await ProfileImageCache.shared.signedURL(for: path)
            let (data, _) = try await URLSession.shared.data(from: url)
            if let ui = UIImage(data: data) {
                ProfileImageCache.shared.cache(image: ui, for: path)
                image = ui
            }
        } catch {
            image = nil
        }
    }
}
