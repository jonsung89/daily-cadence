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
    /// Returns `nil` for media notes — those are kept client-side only
    /// until the Storage upload pipeline lands (Phase F+).
    @discardableResult
    func insert(_ note: MockNote, userId: UUID) async throws -> UUID? {
        if case .media = note.content {
            log.notice("Skipping persistence: media notes need Storage upload (Phase F+)")
            return nil
        }
        try await ensureNoteTypesLoaded()
        guard let typeId = noteTypeIdBySlug[note.type.rawValue] else {
            throw NotesRepositoryError.unknownNoteTypeSlug(note.type.rawValue)
        }
        let payload = encodeForInsert(note, userId: userId, typeId: typeId)
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
    /// stay fixed (RLS scopes the update to rows the user owns); we
    /// re-encode the rest from the in-memory `MockNote`. Media notes are
    /// skipped same as `insert(_:userId:)` — Storage upload pipeline first.
    func update(_ note: MockNote, userId: UUID) async throws {
        if case .media = note.content {
            log.notice("Skipping update: media notes need Storage upload (Phase F+)")
            return
        }
        try await ensureNoteTypesLoaded()
        guard let typeId = noteTypeIdBySlug[note.type.rawValue] else {
            throw NotesRepositoryError.unknownNoteTypeSlug(note.type.rawValue)
        }
        let payload = encodeForInsert(note, userId: userId, typeId: typeId)
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

    private func encodeForInsert(_ note: MockNote, userId: UUID, typeId: UUID) -> NoteRowInsert {
        let title: String?
        let body: [BodyBlockDTO]
        let structuredData: StructuredDataDTO?

        switch note.content {
        case .text(let t, let blocks):
            title = t.isEmpty ? nil : t
            body = blocks.compactMap(encodeBlock(_:))
            structuredData = nil
        case .stat(let t, let value, let sub):
            title = t.isEmpty ? nil : t
            body = []
            structuredData = .stat(value: value, sub: sub)
        case .list(let t, let items):
            title = t.isEmpty ? nil : t
            body = []
            structuredData = .list(items: items)
        case .quote(let text):
            title = nil
            body = []
            structuredData = .quote(text: text)
        case .media:
            // Caller filtered this out in `insert(_:userId:)`; if we get
            // here it's a programming error.
            preconditionFailure("encodeForInsert called with media note")
        }

        return NoteRowInsert(
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

    private func encodeBlock(_ block: TextBlock) -> BodyBlockDTO? {
        switch block.kind {
        case .paragraph(let attr):
            // Phase E.2 polish (fontId / colorId AttributedStringKeys) lands
            // separately. For now paragraphs persist as plain text, losing
            // per-run styling on the round-trip.
            return .paragraph(text: String(attr.characters))
        case .media:
            // Inline media blocks need Storage upload. Skip until F+.
            return nil
        }
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
        } else {
            // Default: text variant, body blocks → paragraph TextBlocks.
            let blocks: [TextBlock] = row.body.compactMap { dto in
                switch dto {
                case .paragraph(let text):
                    return .paragraph(AttributedString(text))
                case .media:
                    // Inline media blocks aren't reconstructable without
                    // their bytes (Phase F+). Drop on decode so the rest of
                    // the body still renders.
                    return nil
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

/// Insert payload — only the fields the client controls. id, created_at,
/// updated_at are server-generated.
private struct NoteRowInsert: Encodable {
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
    case media(aspect: Double, caption: String?)

    private enum CodingKeys: String, CodingKey {
        case kind, text, aspect, caption
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
            self = .media(
                aspect: try c.decodeIfPresent(Double.self, forKey: .aspect) ?? 1.0,
                caption: try c.decodeIfPresent(String.self, forKey: .caption)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .paragraph(let text):
            try c.encode(Kind.paragraph, forKey: .kind)
            try c.encode(text, forKey: .text)
        case .media(let aspect, let caption):
            try c.encode(Kind.media, forKey: .kind)
            try c.encode(aspect, forKey: .aspect)
            try c.encodeIfPresent(caption, forKey: .caption)
        }
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
