import Foundation
import OSLog
import Supabase

/// CRUD against the `notes` table for the signed-in user.
///
/// Phase F.0.2 scope:
/// - **Round-trips:** title, body (paragraph blocks as plain text), structured_data
///   for `.stat` / `.list` / `.quote`, occurred_at, title_style, type via slug-keyed
///   `note_types` cache.
/// - **Client-only (not yet persisted):** media notes (need Storage upload pipeline),
///   image backgrounds, swatch backgrounds (need Storage + backgrounds-library work),
///   AttributedString per-run styling (needs the Phase E.2 polish to introduce
///   `fontId` / `colorId` AttributedStringKeys for round-trip).
/// - **Soft delete:** `delete(id:)` sets `deleted_at = now()`.
///
/// All methods accept the user's UUID rather than reading `AuthStore` directly so
/// the repository stays a pure persistence layer (easier to test, no implicit
/// global dependency at the call site).
enum NotesRepositoryError: Error, LocalizedError {
    case authNotReady
    case unknownNoteTypeSlug(String)
    case unknownNoteTypeId(UUID)

    var errorDescription: String? {
        switch self {
        case .authNotReady:                 return "Auth not ready"
        case .unknownNoteTypeSlug(let s):   return "Unknown note type slug '\(s)'"
        case .unknownNoteTypeId(let id):    return "Unknown note type id \(id)"
        }
    }
}

final class NotesRepository {
    static let shared = NotesRepository()

    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "NotesRepository")

    /// Cached `slug → id` and `id → slug` for `note_types`. The migration seeds
    /// system rows with stable slugs that match `NoteType.rawValue`, so this
    /// loads once and stays valid for the session.
    private var noteTypeIdBySlug: [String: UUID] = [:]
    private var noteTypeSlugById: [UUID: String] = [:]
    private var typesLoaded = false

    private init() {}

    // MARK: - Public CRUD

    /// All non-deleted notes for the user whose `occurred_at` falls within
    /// the local-calendar day containing `day`. Returned oldest first.
    /// Evergreen notes (`occurred_at IS NULL`) are excluded — they live in
    /// a separate "Notes" surface (Phase F+).
    ///
    /// `day` is interpreted in `Calendar.current` (the user's locale +
    /// timezone). Day bounds become `[startOfDay, startOfNextDay)` ISO
    /// timestamps that get sent over the wire as full timestamptz values,
    /// so the server-side comparison matches what the user perceives as
    /// "that day" regardless of where they're physically located.
    ///
    /// Notes with unknown `type_id` (e.g., a custom type that didn't load
    /// in this session) are logged and skipped — better than crashing.
    func fetchForDay(userId: UUID, day: Date) async throws -> [MockNote] {
        try await ensureNoteTypesLoaded()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: day)
        let startOfNext = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? day
        let rows: [NoteRow] = try await AppSupabase.client
            .from("notes")
            .select()
            .eq("user_id", value: userId)
            .is("deleted_at", value: nil)
            .gte("occurred_at", value: startOfDay)
            .lt("occurred_at", value: startOfNext)
            .order("occurred_at", ascending: true)
            .execute()
            .value
        // Phase F.1.2.bgpersist — `decode` is async because notes with
        // an `image` background do a per-row Storage fetch. Serial loop
        // (vs `withTaskGroup` + concurrent decode) is fine for typical
        // day loads (5-15 notes, mostly without backgrounds); revisit if
        // we hit a use case with many image-bg notes per day.
        var notes: [MockNote] = []
        notes.reserveCapacity(rows.count)
        for row in rows {
            if let note = await decode(row) { notes.append(note) }
        }
        log.info("Fetched \(notes.count) notes for \(startOfDay)..<\(startOfNext) (\(rows.count - notes.count) skipped)")
        return notes
    }

    /// Phase F.1.2.weekstrip — returns the set of local-calendar days
    /// within the week containing `day` that have at least one
    /// non-deleted note for `userId`. Powers the Today screen's week
    /// strip indicator: each filled day shows a sage dot, empty days
    /// an outline.
    ///
    /// Selects only `occurred_at` (not the full row body) so the query
    /// stays small. Notes with NULL `occurred_at` (evergreen — Phase
    /// F+) don't belong on a dated week strip and are filtered server-
    /// side via `gte`/`lt` on the column.
    func fetchDaysWithNotes(userId: UUID, weekContaining day: Date) async throws -> Set<Date> {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: day) else { return [] }
        let rows: [OccurredAtRow] = try await AppSupabase.client
            .from("notes")
            .select("occurred_at")
            .eq("user_id", value: userId)
            .is("deleted_at", value: nil)
            .gte("occurred_at", value: interval.start)
            .lt("occurred_at", value: interval.end)
            .execute()
            .value
        return Set(rows.compactMap { row in
            row.occurred_at.flatMap { cal.startOfDay(for: $0) }
        })
    }

    /// Persists a new note. Returns the server-assigned `id` so the caller
    /// can replace the optimistic client UUID with the canonical one.
    /// **Phase F.1.1**: media bytes (standalone media notes + inline media
    /// blocks in text bodies) are uploaded to Supabase Storage during
    /// encoding; the inserted row's `body` contains `MediaRef`s, not bytes.
    @discardableResult
    func insert(_ note: MockNote, userId: UUID) async throws -> UUID? {
        try await ensureNoteTypesLoaded()
        guard let typeId = noteTypeIdBySlug[note.type.rawValue] else {
            throw NotesRepositoryError.unknownNoteTypeSlug(note.type.rawValue)
        }
        let payload = try await encodeForInsert(note, userId: userId, typeId: typeId)
        let row: NoteRow = try await AppSupabase.client
            .from("notes")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        log.info("Inserted note: id=\(row.id) type=\(note.type.rawValue)")
        return row.id
    }

    /// Updates an existing note's mutable fields. The `id` and `user_id`
    /// stay fixed (RLS scopes the update to rows the user owns). Re-uploads
    /// any media bytes whose `MediaPayload.ref` is nil (newly-attached
    /// media); leaves already-uploaded refs untouched.
    func update(_ note: MockNote, userId: UUID) async throws {
        try await ensureNoteTypesLoaded()
        guard let typeId = noteTypeIdBySlug[note.type.rawValue] else {
            throw NotesRepositoryError.unknownNoteTypeSlug(note.type.rawValue)
        }
        let payload = try await encodeForInsert(note, userId: userId, typeId: typeId)
        try await AppSupabase.client
            .from("notes")
            .update(payload)
            .eq("id", value: note.id)
            .execute()
        log.info("Updated note: id=\(note.id) type=\(note.type.rawValue)")
    }

    /// Soft-delete: sets `deleted_at = now()`. The 30-day hard-delete sweep
    /// is server-side (a future `pg_cron` job).
    func delete(id: UUID) async throws {
        struct DeletePatch: Encodable { let deleted_at: Date }
        try await AppSupabase.client
            .from("notes")
            .update(DeletePatch(deleted_at: .now))
            .eq("id", value: id)
            .execute()
        log.info("Soft-deleted note id=\(id)")
    }

    // MARK: - note_types cache

    private func ensureNoteTypesLoaded() async throws {
        if typesLoaded { return }
        let rows: [NoteTypeRow] = try await AppSupabase.client
            .from("note_types")
            .select("id, slug")
            .is("created_by_user_id", value: nil)
            .execute()
            .value
        for row in rows {
            noteTypeIdBySlug[row.slug] = row.id
            noteTypeSlugById[row.id] = row.slug
        }
        typesLoaded = true
        log.info("Loaded \(rows.count) system note_types")
    }

    // MARK: - Encode (client → server)

    private func encodeForInsert(_ note: MockNote, userId: UUID, typeId: UUID) async throws -> NoteRowInsert {
        let title: String?
        var body: [BodyBlockDTO] = []
        let structuredData: StructuredDataDTO?

        switch note.content {
        case .text(let t, let blocks):
            title = t.isEmpty ? nil : t
            for block in blocks {
                if let dto = try await encodeBlock(block, userId: userId) {
                    body.append(dto)
                }
            }
            structuredData = nil
        case .stat(let t, let value, let sub):
            title = t.isEmpty ? nil : t
            structuredData = .stat(value: value, sub: sub)
        case .list(let t, let items):
            title = t.isEmpty ? nil : t
            structuredData = .list(items: items)
        case .quote(let text):
            title = nil
            structuredData = .quote(text: text)
        case .media(let payload):
            // Standalone media note — body holds a single media block,
            // no title (caption serves as the visual content), no
            // structured_data.
            title = nil
            structuredData = nil
            let dto = try await encodeMediaBlock(payload, userId: userId, size: nil)
            body = [dto]
        }

        // Phase F.1.2.bgpersist — encode the note's background. Image
        // backgrounds upload bytes to the `note-backgrounds` Storage
        // bucket and INSERT a `backgrounds` row whose id we link via
        // `notes.background_id`. Color (swatch) backgrounds are not yet
        // persisted — separate Phase F+ TODO for the swatch ↔ background
        // resolver. Failures bubble up; the note insert won't fly with
        // a half-written background.
        let backgroundId = try await encodeBackground(note.background, userId: userId)

        return NoteRowInsert(
            id: note.id,
            user_id: userId,
            type_id: typeId,
            title: title,
            body: body,
            structured_data: structuredData,
            occurred_at: note.occurredAt,
            title_style: note.titleStyle.flatMap(TitleStyleDTO.init(from:)),
            background_id: backgroundId,
            position: nil
        )
    }

    /// Phase F.1.2.bgpersist — uploads image-background bytes to Storage
    /// and inserts a `backgrounds` row, returning the new row's id (which
    /// becomes `notes.background_id`). Returns nil for `nil` and `.color`
    /// backgrounds (the latter is deferred to a separate F+ TODO that
    /// resolves swatches against the seeded `backgrounds` library rows).
    ///
    /// **Known inefficiency for this round.** Each save re-uploads the
    /// background bytes — `MockNote.ImageBackground` doesn't carry a ref,
    /// so encode can't tell "same bytes as last save" from "user picked
    /// a new image." Old `backgrounds` rows + Storage objects become
    /// orphans on every edit. Cleanup via a `pg_cron` GC job + a future
    /// `ref` field on `ImageBackground` are deferred to Phase F+.
    private func encodeBackground(_ background: MockNote.Background?, userId: UUID) async throws -> UUID? {
        guard let background else { return nil }
        switch background {
        case .color(let swatchId):
            // Phase F.1.2.swatchpersist — find-or-INSERT a per-user
            // `backgrounds` row for this swatch. SELECT first (most users
            // re-pick the same handful of swatches, so the cache hit rate
            // is high in practice); if missing, INSERT a new row keyed
            // by the design-system swatch id. Future enhancement: an
            // in-memory `swatchId → backgrounds.id` cache to skip the
            // SELECT after the first hit per session. Phase 1 lookups
            // are 1 row each, RLS-scoped to the user — cheap enough.
            if let existing = try await fetchBackgroundIdForSwatch(swatchId, userId: userId) {
                return existing
            }
            let row = BackgroundRowInsert(
                user_id: userId,
                label: nil,
                kind: "color",
                swatch_id: swatchId,
                color_hex: nil,
                image_url: nil,
                opacity: 1.0
            )
            let inserted: BackgroundRow = try await AppSupabase.client
                .from("backgrounds")
                .insert(row, returning: .representation)
                .select()
                .single()
                .execute()
                .value
            log.info("Inserted swatch backgrounds row id=\(inserted.id) swatch=\(swatchId)")
            return inserted.id
        case .image(let img):
            let storage = MediaStorageProvider.backgrounds
            let ref = try await storage.upload(
                img.imageData,
                contentType: "image/jpeg",
                userId: userId,
                filename: "\(UUID().uuidString.lowercased()).jpg"
            )
            let row = BackgroundRowInsert(
                user_id: userId,
                label: nil,
                kind: "image",
                swatch_id: nil,
                color_hex: nil,
                image_url: ref.path,
                opacity: img.opacity
            )
            let inserted: BackgroundRow = try await AppSupabase.client
                .from("backgrounds")
                .insert(row, returning: .representation)
                .select()
                .single()
                .execute()
                .value
            log.info("Inserted backgrounds row id=\(inserted.id) image_url=\(ref.path)")
            return inserted.id
        }
    }

    /// Phase F.1.2.bgpersist + F.1.2.swatchpersist — fetches a
    /// `backgrounds` row by id and resolves it back to a
    /// `MockNote.Background`. Image rows reconstruct a `MediaRef` from
    /// the stored bucket path, sign a short-lived URL, and download
    /// bytes. Color (swatch) rows resolve to `.color(swatchId)` directly
    /// from the row's `swatch_id` column — the iOS palette repository
    /// renders the actual color from the design-system swatch JSON, so
    /// the row only needs to remember the swatch id.
    ///
    /// Errors are caught and logged rather than thrown — a missing /
    /// network-failed background shouldn't take down the whole note.
    /// The note loads with no background; the user can re-pick to
    /// recover.
    private func fetchBackground(id: UUID) async -> MockNote.Background? {
        do {
            let row: BackgroundRow = try await AppSupabase.client
                .from("backgrounds")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
            switch row.kind {
            case "image":
                guard let path = row.image_url else { return nil }
                let ref = MediaRef(provider: SupabaseStorageImpl.id, path: path)
                let storage = MediaStorageProvider.backgrounds
                let signed = try await storage.signedURL(for: ref, ttlSeconds: 3000)
                let (data, _) = try await URLSession.shared.data(from: signed)
                // Phase F.1.2.bgcache — pass the row id as the
                // `BackgroundImageCache` key so card re-renders skip
                // the re-decode (sub-perceptible per render but stacks
                // visibly under refetch-induced cascades).
                return .image(MockNote.ImageBackground(
                    imageData: data,
                    opacity: row.opacity,
                    cacheKey: row.id.uuidString
                ))
            case "color":
                guard let swatchId = row.swatch_id else { return nil }
                return .color(swatchId: swatchId)
            default:
                return nil
            }
        } catch {
            log.warning("fetchBackground(id: \(id)) failed: \(error.localizedDescription) — note loads without background")
            return nil
        }
    }

    /// Phase F.1.2.swatchpersist — looks up an existing `backgrounds`
    /// row for the given swatch id, scoped to the user (RLS will only
    /// return their own rows). Returns nil if no row exists yet — the
    /// caller then INSERTs a fresh one. Picks the oldest matching row
    /// if duplicates exist (shouldn't happen but defensive — race with
    /// concurrent inserts could in theory create dupes; we just stick
    /// with whichever wins, no harm).
    private func fetchBackgroundIdForSwatch(_ swatchId: String, userId: UUID) async throws -> UUID? {
        struct IdRow: Decodable { let id: UUID }
        let rows: [IdRow] = try await AppSupabase.client
            .from("backgrounds")
            .select("id")
            .eq("user_id", value: userId)
            .eq("kind", value: "color")
            .eq("swatch_id", value: swatchId)
            .order("created_at", ascending: true)
            .limit(1)
            .execute()
            .value
        return rows.first?.id
    }

    private func encodeBlock(_ block: TextBlock, userId: UUID) async throws -> BodyBlockDTO? {
        switch block.kind {
        case .paragraph(let attr):
            // Phase E.2 polish (fontId / colorId AttributedStringKeys) lands
            // separately. For now paragraphs persist as plain text, losing
            // per-run styling on the round-trip.
            return .paragraph(text: String(attr.characters))
        case .media(let payload, let size):
            return try await encodeMediaBlock(payload, userId: userId, size: size)
        }
    }

    /// Phase F.1.1 — uploads media bytes to Storage (when not already
    /// uploaded) and returns the body block DTO with refs filled in.
    /// Skips uploads when the payload's ref is already set (e.g., editing
    /// a previously-uploaded note re-saves the same media block).
    /// Phase F.1.1b — also uploads image thumbnails (`thumbnailData`)
    /// alongside the full asset; the ext + content-type derive from kind.
    private func encodeMediaBlock(
        _ payload: MediaPayload,
        userId: UUID,
        size: MediaBlockSize?
    ) async throws -> BodyBlockDTO {
        let storage = MediaStorageProvider.current

        // Asset extensions / content types per kind. Images are HEIC after
        // F.1.1b; videos are MP4 (HEVC). Falls back to JPEG/MOV labels
        // only for legacy/edge bytes — encoding always produces HEIC/HEVC.
        let assetExt: String = (payload.kind == .video) ? "mp4" : "heic"
        let assetContentType: String = (payload.kind == .video) ? "video/mp4" : "image/heic"

        // Upload the full asset if we have inline bytes and no existing ref.
        let assetRef: MediaRef
        if let existing = payload.ref {
            assetRef = existing
        } else if let data = payload.data {
            assetRef = try await storage.upload(
                data,
                contentType: assetContentType,
                userId: userId,
                filename: "\(UUID().uuidString.lowercased()).\(assetExt)"
            )
        } else {
            throw NotesRepositoryError.unknownNoteTypeSlug("media payload without bytes or ref")
        }

        // Upload poster (videos only) when we have inline bytes.
        let posterRef: MediaRef?
        if let existing = payload.posterRef {
            posterRef = existing
        } else if payload.kind == .video, let posterBytes = payload.posterData {
            posterRef = try await storage.upload(
                posterBytes,
                contentType: "image/jpeg",
                userId: userId,
                filename: "\(UUID().uuidString.lowercased())-poster.jpg"
            )
        } else {
            posterRef = nil
        }

        // Upload thumbnail (images only) — Phase F.1.1b dual-size.
        let thumbnailRef: MediaRef?
        if let existing = payload.thumbnailRef {
            thumbnailRef = existing
        } else if payload.kind == .image, let thumbBytes = payload.thumbnailData {
            thumbnailRef = try await storage.upload(
                thumbBytes,
                contentType: "image/heic",
                userId: userId,
                filename: "\(UUID().uuidString.lowercased())-thumb.heic"
            )
        } else {
            thumbnailRef = nil
        }

        return .media(MediaBlockDTO(
            mediaKind: payload.kind,
            aspect: Double(payload.aspectRatio),
            caption: payload.caption,
            capturedAt: payload.capturedAt,
            size: size?.rawValue,
            ref: assetRef,
            posterRef: posterRef,
            thumbnailRef: thumbnailRef
        ))
    }

    // MARK: - Decode (server → client)

    /// Phase F.1.2.bgpersist — became `async` so background fetches can
    /// happen inline with the rest of the row decode. Backgrounds need a
    /// separate `backgrounds` table SELECT + a Storage signed-URL fetch
    /// for image bytes; doing this here keeps the `MockNote` returned to
    /// callers fully populated. The bg fetch is wrapped in a graceful
    /// catch (logs + returns nil), so a failed background still returns
    /// the note with no background — never blocks loading the rest.
    private func decode(_ row: NoteRow) async -> MockNote? {
        guard let slug = noteTypeSlugById[row.type_id],
              let type = NoteType(rawValue: slug)
        else {
            log.warning("Skipping note \(row.id): unresolved type_id=\(row.type_id)")
            return nil
        }

        let content: MockNote.Content
        if let sd = row.structured_data {
            switch sd {
            case .stat(let value, let sub):
                content = .stat(title: row.title ?? "", value: value, sub: sub)
            case .list(let items):
                content = .list(title: row.title ?? "", items: items)
            case .quote(let text):
                content = .quote(text: text)
            }
        } else if type == .media,
                  case let .media(media)? = row.body.first,
                  row.body.count == 1 {
            // Standalone media note: body has exactly one media block,
            // structured_data is null, type slug is "media".
            content = .media(media.toPayload())
        } else {
            // Default: text variant, body blocks → paragraph + inline
            // media TextBlocks. Inline media is reconstructed with refs
            // populated and inline bytes nil (lazy fetch via MediaResolver).
            let blocks: [TextBlock] = row.body.compactMap { dto -> TextBlock? in
                switch dto {
                case .paragraph(let text):
                    return .paragraph(AttributedString(text))
                case .media(let m):
                    let size = m.size.flatMap(MediaBlockSize.init(rawValue:)) ?? .medium
                    return TextBlock(kind: .media(m.toPayload(), size: size))
                }
            }
            content = .text(title: row.title ?? "", body: blocks)
        }

        let background: MockNote.Background? = await {
            guard let bgId = row.background_id else { return nil }
            return await fetchBackground(id: bgId)
        }()

        return MockNote(
            id: row.id,
            occurredAt: row.occurred_at,
            type: type,
            content: content,
            background: background,
            titleStyle: row.title_style?.toTextStyle()
        )
    }
}

// MARK: - DTOs

/// Mirror of the `note_types` table for the slug↔id cache.
private struct NoteTypeRow: Decodable {
    let id: UUID
    let slug: String
}

/// Phase F.1.2.weekstrip — narrow projection used by
/// `fetchDaysWithNotes`. Selecting only the timestamp column keeps
/// the query payload tiny (a 7-day week typically returns < 100 rows
/// even for a heavy logger).
private struct OccurredAtRow: Decodable {
    let occurred_at: Date?
}

/// Mirror of the `notes` table for `select()` reads.
private struct NoteRow: Decodable {
    let id: UUID
    let user_id: UUID
    let type_id: UUID
    let title: String?
    let body: [BodyBlockDTO]
    let structured_data: StructuredDataDTO?
    let occurred_at: Date?
    let title_style: TitleStyleDTO?
    let background_id: UUID?
    let pinned_at: Date?
    let completed_at: Date?
    let cancelled_at: Date?
    let deleted_at: Date?
    let position: Double?
    let created_at: Date
    let updated_at: Date
}

/// Phase F.1.2.bgpersist — mirror of the `backgrounds` table. Fetched
/// per-note when a note's `background_id` is non-nil. Schema accommodates
/// both color (`swatch_id` / `color_hex`) and image (`image_url`) kinds —
/// this round only writes/reads the `image` variant; swatch resolution is
/// a separate Phase F+ TODO.
private struct BackgroundRow: Decodable {
    let id: UUID
    let user_id: UUID?
    let label: String?
    let kind: String          // "color" or "image"
    let swatch_id: String?
    let color_hex: String?
    let image_url: String?    // Bucket-relative path in note-backgrounds, NOT a literal URL
    let opacity: Double
}

/// Insert payload for creating a new `backgrounds` row. Server assigns
/// `id` / `created_at` / `updated_at`; we set `user_id`, `kind`, the
/// kind-specific payload fields, and `opacity`.
private struct BackgroundRowInsert: Encodable {
    let user_id: UUID
    let label: String?
    let kind: String
    let swatch_id: String?
    let color_hex: String?
    let image_url: String?
    let opacity: Double
}

/// Insert payload — `id` is **client-supplied** (matches `MockNote.id`)
/// so the optimistic UI never has to "swap" a server-assigned UUID.
/// Same UUID throughout the lifecycle eliminates a class of races
/// between background uploads and concurrent user actions (delete /
/// edit while an upload is in flight).
///
/// `created_at` / `updated_at` stay server-generated.
private struct NoteRowInsert: Encodable {
    let id: UUID
    let user_id: UUID
    let type_id: UUID
    let title: String?
    let body: [BodyBlockDTO]
    let structured_data: StructuredDataDTO?
    let occurred_at: Date?
    let title_style: TitleStyleDTO?
    let background_id: UUID?
    let position: Double?
}

/// `body jsonb` shape: array of typed blocks. `kind` discriminator follows
/// the schema vocab (`kind` for JSONB shapes; `type` reserved for note
/// category).
private enum BodyBlockDTO: Codable, Hashable {
    case paragraph(text: String)
    case media(MediaBlockDTO)

    private enum CodingKeys: String, CodingKey {
        case kind, text
        // Media block fields (flattened into the same object as `kind`):
        case mediaKind, aspect, caption, capturedAt, size, ref, posterRef, thumbnailRef
    }

    private enum Kind: String, Codable {
        case paragraph, media
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Default to .paragraph on unknown kinds so an admin-panel addition
        // doesn't crash old clients.
        let kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .paragraph
        switch kind {
        case .paragraph:
            self = .paragraph(text: try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        case .media:
            self = .media(MediaBlockDTO(
                mediaKind: (try? c.decode(MediaPayload.Kind.self, forKey: .mediaKind)) ?? .image,
                aspect: try c.decodeIfPresent(Double.self, forKey: .aspect) ?? 1.0,
                caption: try c.decodeIfPresent(String.self, forKey: .caption),
                capturedAt: try c.decodeIfPresent(Date.self, forKey: .capturedAt),
                size: try c.decodeIfPresent(String.self, forKey: .size),
                ref: try c.decodeIfPresent(MediaRef.self, forKey: .ref),
                posterRef: try c.decodeIfPresent(MediaRef.self, forKey: .posterRef),
                thumbnailRef: try c.decodeIfPresent(MediaRef.self, forKey: .thumbnailRef)
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .paragraph(let text):
            try c.encode(Kind.paragraph, forKey: .kind)
            try c.encode(text, forKey: .text)
        case .media(let m):
            try c.encode(Kind.media, forKey: .kind)
            try c.encode(m.mediaKind, forKey: .mediaKind)
            try c.encode(m.aspect, forKey: .aspect)
            try c.encodeIfPresent(m.caption, forKey: .caption)
            try c.encodeIfPresent(m.capturedAt, forKey: .capturedAt)
            try c.encodeIfPresent(m.size, forKey: .size)
            try c.encodeIfPresent(m.ref, forKey: .ref)
            try c.encodeIfPresent(m.posterRef, forKey: .posterRef)
            try c.encodeIfPresent(m.thumbnailRef, forKey: .thumbnailRef)
        }
    }
}

/// Flattened media-block fields. Kept separate from the parent enum so
/// it's easy to pass around and keeps the encode/decode site readable.
private struct MediaBlockDTO: Codable, Hashable {
    let mediaKind: MediaPayload.Kind
    let aspect: Double
    let caption: String?
    /// Phase F.1.2.exifdate — wall-clock capture moment surfaced in the
    /// viewer's metadata overlay. nil for assets without EXIF / creation
    /// metadata, and for notes saved before this field landed.
    let capturedAt: Date?
    /// Size hint for inline media blocks (`small` / `medium` / `large`).
    /// nil for standalone media notes — the whole card IS the media.
    let size: String?
    let ref: MediaRef?
    let posterRef: MediaRef?
    /// Phase F.1.1b — small image thumbnail ref. Set for image notes;
    /// nil for video (use `posterRef`). Cards prefer this over `ref`.
    let thumbnailRef: MediaRef?

    /// Reconstruct an in-memory `MediaPayload` for a fetched note. Bytes
    /// are nil; refs drive lazy resolution via `MediaResolver`.
    func toPayload() -> MediaPayload {
        MediaPayload(
            kind: mediaKind,
            data: nil,
            posterData: nil,
            thumbnailData: nil,
            aspectRatio: CGFloat(aspect),
            caption: caption,
            capturedAt: capturedAt,
            ref: ref,
            posterRef: posterRef,
            thumbnailRef: thumbnailRef
        )
    }
}

/// `structured_data jsonb` shape — only set on non-text content variants.
/// `kind` discriminator (matching the schema's `kind` vocab for JSONB).
private enum StructuredDataDTO: Codable, Hashable {
    case stat(value: String, sub: String?)
    case list(items: [String])
    case quote(text: String)

    private enum CodingKeys: String, CodingKey {
        case kind, value, sub, items, text
    }

    private enum Kind: String, Codable {
        case stat, list, quote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .stat:
            self = .stat(
                value: try c.decode(String.self, forKey: .value),
                sub: try c.decodeIfPresent(String.self, forKey: .sub)
            )
        case .list:
            self = .list(items: try c.decode([String].self, forKey: .items))
        case .quote:
            self = .quote(text: try c.decode(String.self, forKey: .text))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stat(let value, let sub):
            try c.encode(Kind.stat, forKey: .kind)
            try c.encode(value, forKey: .value)
            try c.encodeIfPresent(sub, forKey: .sub)
        case .list(let items):
            try c.encode(Kind.list, forKey: .kind)
            try c.encode(items, forKey: .items)
        case .quote(let text):
            try c.encode(Kind.quote, forKey: .kind)
            try c.encode(text, forKey: .text)
        }
    }
}

/// `title_style jsonb` shape mirroring `Models/TextStyle.swift`.
private struct TitleStyleDTO: Codable, Hashable {
    let fontId: String?
    let colorId: String?

    init?(from style: TextStyle) {
        // Drop empty styles so we don't write `{fontId: null, colorId: null}`
        // when the user hasn't picked anything.
        if style.isEmpty { return nil }
        self.fontId = style.fontId
        self.colorId = style.colorId
    }

    func toTextStyle() -> TextStyle {
        TextStyle(fontId: fontId, colorId: colorId)
    }
}
