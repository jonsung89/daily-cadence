import Foundation
import UIKit

/// Phase F.1.2.bgcache — process-wide cache of decoded `UIImage`s for
/// note background photos. Keyed by the `backgrounds.id` UUID-string
/// (stable across app launches, RLS-scoped to the user). Solves the
/// "image-bg card flickers when re-rendered" problem: without a cache,
/// every body re-evaluation calls `UIImage(data:)` which re-decodes the
/// JPEG bytes — even when the underlying photo is unchanged. The
/// re-decode is sub-perceptible at typical sizes but stacks visibly when
/// the parent view re-renders (e.g., when `hasLoaded` flips during a
/// post-navigation refetch and cascades through `TimelineScreen`).
///
/// **Pattern**: identical shape to what `SDWebImage` / `Kingfisher` /
/// `Nuke` use internally for their decoded-image tier, and to what
/// `URLCache` + `NSCache` provide for SwiftUI's own `AsyncImage`. Apple's
/// UIKit uses NSCache extensively for the same reason.
///
/// **Why NSCache** (not a plain `[String: UIImage]`): NSCache automatic
/// eviction under memory pressure means we don't have to manage size or
/// reason about cap policies. Concurrency-safe by design.
///
/// **Cache key contract**: caller-provided `key` is the
/// `backgrounds.id.uuidString`. `nil` keys (newly-picked, not-yet-uploaded
/// images) bypass the cache entirely — they render via direct decode.
/// One unavoidable re-decode per render in the editor preview path until
/// the user saves and the row gets an id; the editor session is short
/// enough that this is invisible.
///
/// **No invalidation method needed**: each `backgrounds` row is
/// immutable once written (we always INSERT a new row on edit rather
/// than UPDATE — see Phase F.1.2.bgpersist). So a given key always
/// resolves to the same bytes; once cached, it stays correct until
/// memory eviction.
final class BackgroundImageCache: @unchecked Sendable {
    static let shared = BackgroundImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {}

    /// Returns the decoded image for `key`, hitting cache on subsequent
    /// calls with the same key. `nil` key falls through to direct
    /// decode (no caching). Returns nil only if `UIImage(data:)` itself
    /// returns nil (corrupt bytes).
    func image(forKey key: String?, data: Data) -> UIImage? {
        if let key, let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        guard let image = UIImage(data: data) else { return nil }
        if let key {
            cache.setObject(image, forKey: key as NSString)
        }
        return image
    }
}
