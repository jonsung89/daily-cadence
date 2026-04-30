-- =============================================================================
-- Migration 004: day_marks
-- =============================================================================
-- Per-day emoji markers ("mark a special day") on the Today screen's week
-- strip. One emoji per (user, day). Long-press a day in the strip → picker
-- → emoji renders in the day cell's top-right corner. Designed for the
-- two-user-shared TestFlight: when the household marks an anniversary
-- on one device, both devices show it.
--
-- Schema choices:
--   - `day` is `date` (not `timestamptz`) — calendar-day semantics in the
--     user's timezone are what matter; storing the time-of-day component
--     would invite TZ bugs at midnight rollovers.
--   - `(user_id, day)` is the primary key — one emoji per day per user.
--     Re-marking is an upsert.
--   - `emoji` is `text` (not constrained) — Unicode emojis are variable
--     length (1-7 grapheme clusters with skin tones / ZWJ sequences). A
--     short text column with no length cap is the right shape.
--   - RLS scoped to owner — same pattern as `notes` and `note_collaborators`.
--
-- Re-runnable: `if not exists` on the table, idempotent policy creates.
-- =============================================================================

create table if not exists public.day_marks (
    user_id uuid not null references auth.users(id) on delete cascade,
    day date not null,
    emoji text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (user_id, day)
);

-- Index by user for the "load all marks for me" fetch on launch. The PK
-- `(user_id, day)` already covers point lookups; this index sweeps for
-- bulk reads sorted by day (week-strip and future calendar surfaces).
create index if not exists day_marks_user_day_idx
    on public.day_marks (user_id, day);

-- Privileges: RLS gates rows, GRANT gates the table. Without this,
-- the `authenticated` role gets "permission denied for table day_marks"
-- on every read/write — same gap migration 003 closed for the
-- original tables. Idempotent.
grant select, insert, update, delete on public.day_marks to authenticated;

alter table public.day_marks enable row level security;

drop policy if exists "day_marks_select_owner" on public.day_marks;
create policy "day_marks_select_owner"
    on public.day_marks for select
    using (auth.uid() = user_id);

drop policy if exists "day_marks_insert_owner" on public.day_marks;
create policy "day_marks_insert_owner"
    on public.day_marks for insert
    with check (auth.uid() = user_id);

drop policy if exists "day_marks_update_owner" on public.day_marks;
create policy "day_marks_update_owner"
    on public.day_marks for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "day_marks_delete_owner" on public.day_marks;
create policy "day_marks_delete_owner"
    on public.day_marks for delete
    using (auth.uid() = user_id);

-- Auto-bump `updated_at` on every UPDATE so `created_at` stays the
-- original mark date and `updated_at` reflects emoji changes. The notes
-- table uses the same trigger pattern via `set_updated_at()` (declared
-- in migration 001).

drop trigger if exists day_marks_set_updated_at on public.day_marks;
create trigger day_marks_set_updated_at
    before update on public.day_marks
    for each row execute function public.set_updated_at();
