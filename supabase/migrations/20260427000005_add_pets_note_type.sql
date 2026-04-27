-- Adds the `pets` system note type alongside the existing six categories
-- (workout / meal / sleep / mood / activity / general / media).
--
-- Slug matches `NoteType.rawValue = "pets"` so `NotesRepository`'s
-- slug→id cache resolves it with no app-side changes besides the new
-- enum case. `color_hex` mirrors the iOS `Color.DS.blush` light value
-- (the dark-mode value is resolved client-side via the dynamic color
-- token; the DB stores a single hex for non-iOS clients).
--
-- Re-runnable via `on conflict do nothing` on the `note_types_slug_system_uniq`
-- index (slug + null user).

insert into public.note_types (slug, display_name, color_hex, icon, structured_data_schema)
values
    ('pets', 'Pets', '#F2C9C4', 'pawprint.fill', '{"fields": []}'::jsonb)
on conflict do nothing;
