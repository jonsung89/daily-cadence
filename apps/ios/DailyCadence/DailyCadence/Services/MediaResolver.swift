import Foundation
import OSLog
import UIKit

/// Resolves `MediaRef`s to bytes (and signed URLs) with caching.
///
/// Phase F.1.1 — when a `MediaPayload` was decoded from a server fetch,
/// `data`/`posterData` are nil and `ref`/`posterRef` are set. Renderers
/// call this resolver to get bytes on demand. Two cache layers:
///
/// 1. **Signed-URL cache** (`urlCache`): in-process dictionary, ~50 min
///    TTL. Supabase signed URLs default to 1 hour — caching for 50 min
///    gives a 10-minute buffer so we never serve a URL on the verge of
///    expiry. Avoids re-issuing a URL on every render.
/// 2. **Bytes cache via `URLCache.shared`** (HTTP-level, on-disk +
///    memory): the system-wide `URLSession` cache that Apple's
///    `URLSession.shared` uses by default. Returns cached responses
///    when the URL is identical — and signed URLs are stable for the
///    cached TTL window. Disk cache survives app relaunch (until the
///    OS purges or we evict).
///
/// Phase F.1.1c will add an `NSCache<NSString, UIImage>` decoded-image
/// layer on top so per-scroll rendering doesn't repeatedly re-decode the
/// same JPEG/HEIC.
@Observable
final class MediaResolver {
    static let shared = MediaResolver()

    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "MediaResolver")

    /// Per-ref signed URL cache. Key: ref; value: (url, fetchedAt).
    private var urlCache: [MediaRef: (url: URL, fetchedAt: Date)] = [:]
    private let urlTTL: TimeInterval = 50 * 60

    private init() {
        // Tune the shared URLCache for media bytes. Defaults are tiny
        // (~512 KB memory + 10 MB disk) — bump to 50 MB / 200 MB so a
        // typical day's worth of fetched media stays cached across the
        // app's lifetime + survives a relaunch.
        URLCache.shared.memoryCapacity = 50 * 1024 * 1024
        URLCache.shared.diskCapacity = 200 * 1024 * 1024
    }

    // MARK: - Signed URL

    /// Returns a (cached) signed URL for `ref`. Re-issues when the cached
    /// entry is older than `urlTTL`.
    func signedURL(for ref: MediaRef) async throws -> URL {
        if let cached = urlCache[ref],
           Date().timeIntervalSince(cached.fetchedAt) < urlTTL {
            return cached.url
        }
        guard let impl = MediaStorageProvider.impl(for: ref) else {
            log.error("No storage impl registered for provider '\(ref.provider)'")
            throw URLError(.unsupportedURL)
        }
        let url = try await impl.signedURL(for: ref, ttlSeconds: 60 * 60)
        urlCache[ref] = (url, Date())
        return url
    }

    // MARK: - Bytes

    /// Returns the bytes for the full asset of `payload`. Inline first
    /// (no fetch), then via `payload.ref` through the URL+URLCache layer.
    /// `nil` if neither inline nor ref is available.
    func bytes(for payload: MediaPayload) async throws -> Data? {
        if let data = payload.data { return data }
        guard let ref = payload.ref else { return nil }
        return try await fetchBytes(for: ref)
    }

    /// Returns the bytes to display as the card preview. Kind-aware:
    /// image → thumbnail (F.1.1b dual-size), video → first-frame poster.
    /// Inline-bytes fast-paths come first; refs are the lazy-load
    /// fallback.
    func posterBytes(for payload: MediaPayload) async throws -> Data? {
        switch payload.kind {
        case .image:
            // Prefer the small HEIC thumbnail (~80 KB) over the full
            // asset (~400 KB). 5-10× egress reduction since most user
            // time is spent scanning cards, not fullscreen viewing.
            if let inline = payload.thumbnailData { return inline }
            if let thumbRef = payload.thumbnailRef {
                return try await fetchBytes(for: thumbRef)
            }
            // Pre-F.1.1b notes have no thumbnail — fall back to full.
            if let inline = payload.data { return inline }
            if let ref = payload.ref {
                return try await fetchBytes(for: ref)
            }
            return nil
        case .video:
            if let inline = payload.posterData { return inline }
            if let posterRef = payload.posterRef {
                return try await fetchBytes(for: posterRef)
            }
            return nil
        }
    }

    /// Lower-level: fetch bytes for an arbitrary ref. Goes through
    /// `URLSession.shared` so `URLCache.shared` can serve from disk on
    /// repeat fetches.
    func fetchBytes(for ref: MediaRef) async throws -> Data {
        let url = try await signedURL(for: ref)
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
