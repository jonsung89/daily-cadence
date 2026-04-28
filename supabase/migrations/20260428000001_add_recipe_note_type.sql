-- Adds the `recipe` system note type (Phase F.1.2.recipe) — 9th system
-- type. Use case: snap a recipe screenshot, add a title + food type
-- + tags so it's findable later. Slug matches `NoteType.rawValue =
-- "recipe"` so `NotesRepository`'s slug→id cache resolves it without
-- code changes beyond the new enum case + color tokens.
--
-- `color_hex` mirrors the iOS `Color.DS.recipe` light value (#CC462D
-- — paprika red, distinct from meal's amber and workout's
-- terracotta-brown). Dark-mode value resolves client-side via the
-- dynamic color token.
--
-- `structured_data_schema` is **populated** for this row — recipe
-- notes will surface a few optional fields above the free-form body
-- when the future structured-data renderer ships (Phase F+ TODO):
--   • title       — recipe name (string)
--   • food_type   — broad category, free-form ("Korean", "Italian",
--                   "Dessert"); not enum-constrained so users can
--                   organise however they want
--   • tags        — searchable free-form tags (text[]) — "spicy",
--                   "soup", "weeknight", "date-night," etc. Powers the
--                   future cross-note search feature.
--   • is_favorite — toggle so the user can star recipes they want to
--                   make again
--
-- The body remains the primary surface — recipe notes are about
-- "screenshot + thoughts," with these fields as scaffolding the
-- search UX uses to surface them later. Existing clients without the
-- renderer ignore the schema; the body editor still works.
--
-- Re-runnable via `on conflict do nothing` against the
-- `note_types_slug_system_uniq` index (slug + null user).

insert into public.note_types (slug, display_name, color_hex, icon, structured_data_schema)
values
    (
        'recipe',
        'Recipe',
        '#CC462D',
        'frying.pan.fill',
        '{"fields": [
            {"key": "title",       "type": "string",   "required": false},
            {"key": "food_type",   "type": "string",   "required": false},
            {"key": "tags",        "type": "string[]", "required": false},
            {"key": "is_favorite", "type": "bool",     "required": false}
        ]}'::jsonb
    )
on conflict do nothing;
