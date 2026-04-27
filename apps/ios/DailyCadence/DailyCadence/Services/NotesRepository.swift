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
        let notes = rows.compactMap(decode(_:))
        log.info("Fetched \(notes.count) notes for \(startOfDay)..<\(startOfNext) (\(rows.count - notes.count) skipped)")
        return notes
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

        return NoteRowInsert(
            id: note.id,
            user_id: userId,
            type_id: typeId,
            title: title,
            body: body,
            structured_data: structuredData,
            occurred_at: note.occurredAt,
            title_style: note.titleStyle.flatMap(TitleStyleDTO.init(from:)),
            background_id: nil,
            position: nil
        )
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
            size: size?.rawValue,
            ref: assetRef,
            posterRef: posterRef,
            thumbnailRef: thumbnailRef
        ))
    }

    // MARK: - Decode (server → client)

    private func decode(_ row: NoteRow) -> MockNote? {
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

        return MockNote(
            id: row.id,
            occurredAt: row.occurred_at,
            type: type,
            content: content,
            background: nil,
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
    let pinned_at: Date?
    let completed_at: Date?
    let cancelled_at: Date?
    let deleted_at: Date?
    let position: Double?
    let created_at: Date
    let updated_at: Date
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
        case mediaKind, aspect, caption, size, ref, posterRef, thumbnailRef
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
