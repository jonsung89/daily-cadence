import Foundation
import UIKit

/// In-memory cache for the user's profile image. Two layers:
///
/// 1. **Decoded UIImage** keyed by bucket-relative path. Returned
///    instantly on a hit, no network or decode cost. `NSCache` so iOS
///    can purge under memory pressure (profile images are small,
///    purging is rarely an issue).
/// 2. **Signed URL** keyed by path, with a TTL just under the
///    Supabase signed-URL lifetime (50 min). Saves the round-trip to
///    sign on every render; the cached URL is itself cacheable by
///    `URLCache.shared` for the bytes layer.
///
/// Without this, every visit to Settings (or any surface that mounts
/// a `ProfileAvatarImage`) signs a new URL and re-downloads bytes
/// because each signed URL has a unique signature query param,
/// missing `URLCache.shared`. With this, only the first load per
/// session pays the network cost; afterward the avatar renders
/// immediately from the decoded UIImage cache.
@MainActor
final class ProfileImageCache {
    static let shared = ProfileImageCache()

    private let images = NSCache<NSString, UIImage>()
    private var urls: [String: (url: URL, fetchedAt: Date)] = [:]

    /// Same TTL the rest of the app uses for signed URLs (`MediaResolver`).
    /// Trim against the Supabase default of 60 min so we re-sign before
    /// expiry rather than after.
    private let ttl: TimeInterval = 50 * 60

    private init() {
        images.countLimit = 8
    }

    func image(for path: String) -> UIImage? {
        images.object(forKey: path as NSString)
    }

    func cache(image: UIImage, for path: String) {
        images.setObject(image, forKey: path as NSString)
    }

    /// Returns a signed URL for `path`, reusing a cached one inside the
    /// TTL window. The Supabase Storage API returns a fresh signed URL
    /// on each call — we cache locally so renders within the same
    /// session don't re-sign.
    func signedURL(for path: String) async throws -> URL {
        if let entry = urls[path],
           Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.url
        }
        let ref = MediaRef(provider: SupabaseStorageImpl.id, path: path)
        let signed = try await MediaStorageProvider.profileImages
            .signedURL(for: ref, ttlSeconds: 3000)
        urls[path] = (signed, Date())
        return signed
    }

    /// Drop a single path from both layers. Call after upload/remove
    /// so the old path's entries don't linger. Pass nil to clear the
    /// whole cache (useful on sign-out).
    func invalidate(path: String? = nil) {
        if let path {
            images.removeObject(forKey: path as NSString)
            urls[path] = nil
        } else {
            images.removeAllObjects()
            urls.removeAll()
        }
    }
}
