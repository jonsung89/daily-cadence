-- Adds the `book` system note type (Phase F.1.2.book) for reading
-- logs — vet visit notes for pets style but for chapter-by-chapter
-- reading thoughts. Slug matches `NoteType.rawValue = "book"` so
-- `NotesRepository`'s slug→id cache resolves it without code
-- changes beyond the new enum case + color tokens.
--
-- `color_hex` mirrors the iOS `Color.DS.book` light value
-- (#6B4F3A — coffee-brown evoking a leather book binding). Dark-mode
-- value resolves client-side via the dynamic color token.
--
-- `structured_data_schema` is **populated** for this row — book notes
-- will surface a few optional fields above the free-form body when
-- the future structured-data renderer ships (Phase F+ TODO):
--   • title         — book title (string)
--   • author        — book author (string, optional)
--   • progress      — free-form ("Ch 3–5", "p. 122–187", etc.) so the
--                     user isn't constrained to one format
--   • is_finished   — toggle so the user can mark a book complete
--
-- The body remains the primary surface — book notes are about
-- "free-write thoughts and summary," with these fields as light
-- scaffolding rather than a cage. Existing clients without the
-- renderer ignore the schema; the body editor still works.
--
-- Re-runnable via `on conflict do nothing` against the
-- `note_types_slug_system_uniq` index (slug + null user).

insert into public.note_types (slug, display_name, color_hex, icon, structured_data_schema)
values
    (
        'book',
        'Book',
        '#6B4F3A',
        'book.closed.fill',
        '{"fields": [
            {"key": "title",       "type": "string", "required": false},
            {"key": "author",      "type": "string", "required": false},
            {"key": "progress",    "type": "string", "required": false},
            {"key": "is_finished", "type": "bool",   "required": false}
        ]}'::jsonb
    )
on conflict do nothing;
