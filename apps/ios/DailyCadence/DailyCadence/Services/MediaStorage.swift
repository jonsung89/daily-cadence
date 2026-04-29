import Foundation
import OSLog
import Supabase

/// Provider-agnostic media storage abstraction.
///
/// Phase F.1.1 — the iOS app uploads media bytes through `MediaStorage.current`.
/// `current` is wired to `SupabaseStorageImpl` today; when egress costs hit
/// the migration trigger (~$200/mo, ~4-5k DAU) we add `R2StorageImpl` and
/// flip `current` to point at it. Existing `MediaRef`s stay valid — each
/// ref carries its own `provider` field so old refs resolve to the old
/// implementation while new refs resolve to the new one. See
/// `~/.claude/.../memory/project_media_storage.md` for full strategy.
///
/// `MediaRef` is what goes into `notes.body` JSONB — a stable opaque
/// pointer that survives provider migrations. URLs are short-lived
/// (signed URLs, ~1hr TTL) and computed on demand.
protocol MediaStorage: Sendable {
    /// Provider id ("supabase" / "r2" / …) — written into the produced
    /// `MediaRef.provider` so future fetches can resolve back to the
    /// right impl.
    var providerId: String { get }

    /// Uploads bytes to a per-user folder and returns the durable ref.
    /// Path layout: `{userId}/{filename}`. The filename is chosen by the
    /// caller (e.g. `{uuid}.heic`, `{uuid}-thumb.heic`); we don't
    /// generate it here so callers can pair full + thumbnail uploads.
    func upload(
        _ data: Data,
        contentType: String,
        userId: UUID,
        filename: String
    ) async throws -> MediaRef

    /// Issues a signed URL for `ref` valid for `ttlSeconds`. iOS clients
    /// fetch bytes via `URLSession` against this URL. Cache the URL
    /// itself (not the bytes) for ~50 min — the URL-cache layer in
    /// `MediaResolver` does this.
    func signedURL(for ref: MediaRef, ttlSeconds: Int) async throws -> URL

    /// Best-effort delete. Idempotent; doesn't throw if the object is
    /// already gone. Used during note deletion (Phase F+) and the future
    /// R2-migration cleanup.
    func delete(_ ref: MediaRef) async throws
}

/// The opaque pointer stored in `notes.body` JSONB for each media block.
/// Survives provider migrations: a backfill job reuploads bytes to the
/// new provider and rewrites the ref's `provider` field; iOS code
/// resolving the ref dispatches to the matching impl per-ref.
struct MediaRef: Codable, Hashable, Sendable {
    /// Provider id matching some `MediaStorage.providerId`. Future
    /// migrations write a new value here without changing `path`.
    let provider: String
    /// Bucket-relative path. For Supabase that's `{userId}/{filename}`.
    let path: String
}

// MARK: - Provider registry

enum MediaStorageProvider {
    /// The implementation new media uploads should use (note bodies +
    /// standalone media notes). Phase F.1.1 starts at Supabase; flipping
    /// this to an `R2StorageImpl` is the migration.
    static let current: any MediaStorage = SupabaseStorageImpl(bucket: SupabaseStorageImpl.mediaBucket)

    /// Phase F.1.2.bgpersist — separate impl bound to the
    /// `note-backgrounds` bucket. Image-background bytes (per-note
    /// custom photos used as a card background) live here, isolated
    /// from media so RLS / lifecycle / migration concerns don't cross
    /// over. Same auth + Supabase Storage backend underneath; only the
    /// bucket parameter differs.
    static let backgrounds: any MediaStorage = SupabaseStorageImpl(bucket: SupabaseStorageImpl.backgroundsBucket)

    /// Phase F.3.profile — `profile-images` bucket for user profile
    /// photos. Same path layout (`{user_id}/{filename}`) and RLS
    /// pattern as the other buckets. Photo path persists to
    /// `auth.users.raw_user_meta_data.profile_image_path`.
    static let profileImages: any MediaStorage = SupabaseStorageImpl(bucket: SupabaseStorageImpl.profileImagesBucket)

    /// Resolves a `MediaRef` to the right impl by provider id. Used on
    /// fetch — older refs from Supabase keep working even after `current`
    /// flips to R2 because each ref carries its provider. Note: this
    /// doesn't disambiguate the bucket — callers that need a specific
    /// bucket should reach for `current` / `backgrounds` directly.
    static func impl(for ref: MediaRef) -> (any MediaStorage)? {
        switch ref.provider {
        case SupabaseStorageImpl.id: return SupabaseStorageImpl(bucket: SupabaseStorageImpl.mediaBucket)
        // case R2StorageImpl.id: return R2StorageImpl()    // Phase F+
        default: return nil
        }
    }
}

// MARK: - Supabase implementation

struct SupabaseStorageImpl: MediaStorage {
    static let id = "supabase"
    var providerId: String { Self.id }

    /// Buckets created in `supabase/migrations/20260427000002_storage_buckets.sql`.
    /// Per-user folder isolation is enforced by RLS on `storage.objects`
    /// (`(storage.foldername(name))[1] = auth.uid()::text`).
    static let mediaBucket = "note-media"
    static let backgroundsBucket = "note-backgrounds"
    static let profileImagesBucket = "profile-images"

    /// Bucket-scoped — one impl instance per bucket. Phase F.1.2.bgpersist
    /// added this so backgrounds can route to a separate bucket without
    /// duplicating the upload/sign/delete plumbing.
    let bucket: String

    private static let log = Logger(
        subsystem: "com.jonsung.DailyCadence",
        category: "SupabaseStorage"
    )

    func upload(
        _ data: Data,
        contentType: String,
        userId: UUID,
        filename: String
    ) async throws -> MediaRef {
        let path = "\(userId.uuidString.lowercased())/\(filename)"
        let options = FileOptions(
            cacheControl: "3600",
            contentType: contentType,
            // We never overwrite — every upload uses a fresh UUID
            // filename — so leave upsert at the default false.
            upsert: false
        )
        try await AppSupabase.client.storage
            .from(bucket)
            .upload(path, data: data, options: options)
        Self.log.info("Uploaded \(data.count) bytes → \(bucket)/\(path)")
        return MediaRef(provider: Self.id, path: path)
    }

    func signedURL(for ref: MediaRef, ttlSeconds: Int) async throws -> URL {
        try await AppSupabase.client.storage
            .from(bucket)
            .createSignedURL(path: ref.path, expiresIn: ttlSeconds)
    }

    func delete(_ ref: MediaRef) async throws {
        _ = try await AppSupabase.client.storage
            .from(bucket)
            .remove(paths: [ref.path])
        Self.log.info("Deleted \(bucket)/\(ref.path)")
    }
}
