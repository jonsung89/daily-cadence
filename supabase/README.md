# Supabase

Database schema, RLS policies, and storage configuration for DailyCadence.

## Layout

```
supabase/
├── README.md                           ← this file
└── migrations/
    ├── 20260427000001_notes_init.sql       ← notes table + sharing scaffold + RLS
    └── 20260427000002_storage_buckets.sql  ← note-media + note-backgrounds buckets + RLS
```

## How to apply

These migrations follow [Supabase CLI](https://supabase.com/docs/guides/cli) conventions. Once the CLI is installed and the project is linked:

```sh
# from repo root
supabase db push    # applies all unrun migrations to the linked project
```

For ad-hoc / dashboard application: open the SQL editor in the Supabase dashboard and paste the file contents in order. Migrations are idempotent (`if not exists`, `do $$ begin … exception when duplicate_object then null; end $$;`, `drop policy if exists`) so re-running is safe.

## Schema decisions

See `docs/PROGRESS.md` Phase F section for the full design discussion. Summary:

- **Types are data, not enums.** `note_types` table holds system + user-created types. Each carries a `structured_data_schema jsonb` describing the editor fields for notes of that type. Field-`kind` vocabulary is recursive (`object`, `list` with `item_schema`) so arbitrarily nested shapes (e.g., workout exercises with sets/reps/weight) compose without bespoke kinds.
- **Backgrounds are an account-level library.** `backgrounds` table holds system presets + user-created entries. `notes.background_id` is a FK so the same library entry can be reused across notes; editing it propagates.
- **Content shape on `notes`:** hybrid — common fields typed; variant content in `body jsonb` (rich blocks: paragraph/media/checkbox) + `structured_data jsonb` (type-specific fields per the type's schema). No `content_kind` discriminator.
- **Reorder:** fractional indexing (`position double precision`).
- **Soft delete:** `deleted_at timestamptz` nullable, 30-day retention (cleanup job TBD).
- **Media bytes:** Supabase Storage buckets (`note-media`, `note-backgrounds`); URL refs in `body` / `backgrounds.image_url`.
- **Sharing:** unified per-note `note_collaborators` (role + status: invited/accepted/declined/left) for share/invite, plus `shared_groups` + `shared_group_members` (also status-tracked) for group-tag sharing. Only group owners can invite members; members must accept; members can leave. Empty in Phase 1; RLS reads them from day one so adding the share UI later doesn't require policy rewrites.
- **Reminders / TODOs:** orthogonal to `type`. `occurred_at` is **nullable** — NULL = evergreen note (running grocery list, no date). Past = journal. Future = reminder. Plus `completed_at` (done) and `notification_offsets int[]` (notification firing).
- **Reschedule with audit trail:** `cancelled_at` marks notes that didn't happen as planned; `rescheduled_from_id` on the new note points back to the predecessor. UI surfaces "moved to [date]" indicators on cancelled rows.

## Discriminator vocabulary

This schema uses **`kind`** (not `type`) for discriminator fields inside JSONB shapes — `body` block kinds, `backgrounds.kind`, structured-data field kinds. `type` is reserved for the note's category (`note_types.slug`) so the two never collide.

## What's NOT in here yet

- Auth provider configuration (Sign in with Apple, Google) — done via the Supabase **dashboard**, not SQL. Configured during the Phase F session once Apple Developer enrollment clears.
- A `user_settings` table for default reminder offsets etc. — added in a later migration when the notification UI ships.
- A cleanup `pg_cron` job for hard-deleting notes past their 30-day soft-delete window — added when soft-delete UI ships.
- Realtime channels — not needed for solo + family use; foreground refresh is enough.
- Full-text search index — defer until search ships.
