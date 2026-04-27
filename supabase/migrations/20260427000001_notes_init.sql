-- =============================================================================
-- Migration 001: notes_init
-- =============================================================================
-- Initial DailyCadence schema for Phase F (Supabase persistence). Designed
-- as the *single* migration covering Phase 1 use, with future-shaped
-- scaffolding so we don't repaint into a corner later.
--
-- Top-level entities:
--   - note_types         catalog of system + user-created types (with
--                        per-type structured_data field schemas)
--   - backgrounds        account-level library of color/image background
--                        presets, reusable across many notes
--   - notes              the main content table (FKs to type + background)
--   - shared_groups      named groups of users (e.g. "household") that can
--                        be tagged onto a note to auto-share it
--   - shared_group_members
--   - note_collaborators per-note share/invite with role + status
--                        (collapses share + invite into one model)
--
-- Design decisions agreed in the schema-design session:
--
--  1. **Types are data, not enums.** `note_types` table holds system rows
--     (created_by_user_id IS NULL) and user-created rows. Each type carries
--     a `structured_data_schema jsonb` describing the editor fields for
--     notes of that type. New types and new field shapes don't need
--     migrations.
--
--  2. **Backgrounds are an account-level library.** `backgrounds` table
--     holds system presets + user-created entries. `notes.background_id`
--     is a FK so the same library entry can be reused across notes.
--
--  3. **Content shape on `notes`:** hybrid — common fields typed
--     (user_id, type_id, occurred_at, pinned_at, position, deleted_at,
--     cancelled_at, etc.); variant content in `body jsonb` (rich blocks)
--     and `structured_data jsonb` (type-specific fields per the type's
--     schema). No `content_kind` discriminator.
--
--  4. **Reorder:** fractional indexing (`position double precision`).
--
--  5. **Soft delete:** `deleted_at timestamptz` nullable; 30-day retention
--     via a future scheduled cleanup job.
--
--  6. **Media bytes:** NOT in this DB. Live in `note-media` Storage bucket
--     (configured in 002); `body` jsonb carries URL refs.
--
--  7. **Sharing:** unified per-note + group-tag model.
--       - Per-note share/invite via `note_collaborators` (role + status).
--         "Share with viewer" and "invite as editor" are the same row,
--         just different role values. Recipient sees status='invited'
--         until they accept.
--       - Group-tag via `notes.shared_group_id` referencing a named
--         `shared_groups` row. Group membership has its own status
--         lifecycle.
--     RLS reads BOTH share tables from day one. Phase 1 has empty share
--     tables; the EXISTS subqueries short-circuit cheaply.
--
--  8. **Reminders / TODOs:** orthogonal to type. `occurred_at` is
--     **nullable** — NULL = evergreen note (running grocery list, no
--     specific time). Past = journal, future = reminder/todo. Plus
--     `completed_at` (done) and `notification_offsets int[]` (when to
--     fire reminders).
--
--  9. **Reschedule with audit trail.** `cancelled_at` marks notes that
--     didn't happen as planned; `rescheduled_from_id` on the new note
--     points back to the predecessor. UI surfaces "moved to [date]"
--     indicators on cancelled rows.
--
-- 10. **Timestamps stored in UTC** (`timestamptz`). Display-time conversion
--     is the client's responsibility.
--
-- Discriminator vocabulary: this schema uses `kind` (not `type`) for
-- discriminator fields inside JSONB shapes — `body` block kinds, background
-- kinds, structured-data field kinds. `type` is reserved for the note's
-- category (`note_types.slug`) so the two never collide.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Extensions
-- -----------------------------------------------------------------------------

create extension if not exists pgcrypto;  -- gen_random_uuid()


-- -----------------------------------------------------------------------------
-- updated_at trigger function (used by several tables below)
-- -----------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;


-- -----------------------------------------------------------------------------
-- note_types — catalog of system + user-created types
-- -----------------------------------------------------------------------------
-- System types: created_by_user_id IS NULL, visible to everyone.
-- Custom types: created_by_user_id = a specific user, visible only to them.
--
-- `slug` is the stable code-side reference (the iOS app refers to system
-- types by slug, never by id, so `note_types` rows can be re-seeded across
-- environments without breaking the client).
--
-- `structured_data_schema` is the JSON description the editor reads to
-- render type-specific fields. Field kinds form a recursive vocabulary so
-- arbitrarily complex shapes (e.g., workout exercises with sets) compose
-- from primitives without bespoke kinds:
--
--   {
--     "fields": [
--       {"key": "duration_minutes", "label": "Duration", "kind": "number", "unit": "min"},
--       {"key": "exercises", "label": "Exercises", "kind": "list",
--        "item_schema": {
--          "fields": [
--            {"key": "name", "label": "Exercise", "kind": "text"},
--            {"key": "sets", "label": "Sets", "kind": "list",
--             "item_schema": {
--               "fields": [
--                 {"key": "reps", "label": "Reps", "kind": "number"},
--                 {"key": "weight", "label": "Weight", "kind": "number", "unit": "lb"}
--               ]
--             }}
--          ]
--        }}
--     ]
--   }
--
-- Supported `kind` values (open-ended; client falls back to `text` for
-- unknown values so admin-panel additions don't break old clients):
--   text, text_long, number, duration, checkbox, rating, enum, date,
--   time, datetime, object (one nested form), list (array of nested forms)

create table if not exists public.note_types (
    id                      uuid        primary key default gen_random_uuid(),
    slug                    text        not null,
    display_name            text        not null,
    color_hex               text        not null,
    icon                    text        not null,                    -- SF Symbol name OR emoji
    structured_data_schema  jsonb       not null default '{"fields": []}'::jsonb,
    created_by_user_id      uuid        references auth.users(id) on delete cascade,
    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now()
);

-- Slug uniqueness scoped per-owner: system slugs unique across NULL
-- owners; custom-type slugs unique per user. A user can have a custom
-- "workout" type that doesn't conflict with the system one.
create unique index if not exists note_types_slug_system_uniq
    on public.note_types (slug)
    where created_by_user_id is null;

create unique index if not exists note_types_slug_user_uniq
    on public.note_types (created_by_user_id, slug)
    where created_by_user_id is not null;

drop trigger if exists note_types_set_updated_at on public.note_types;
create trigger note_types_set_updated_at
    before update on public.note_types
    for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- backgrounds — account-level library of background presets
-- -----------------------------------------------------------------------------
-- Same NULL-owner pattern as note_types. System presets are shipped with
-- the app; user-created backgrounds (especially photo ones) live in the
-- user's account-level library so they can be reused across notes.
--
-- For `kind = 'color'`: either `swatch_id` (refers to a swatch in the
-- design-system palette) OR `color_hex` (custom hex from the user) is set.
-- For `kind = 'image'`: `image_url` references the note-backgrounds
-- Storage bucket.

create table if not exists public.backgrounds (
    id              uuid        primary key default gen_random_uuid(),
    user_id         uuid        references auth.users(id) on delete cascade,  -- NULL = system preset
    label           text,                                                     -- e.g., "Beach trip"
    kind            text        not null check (kind in ('color', 'image')),
    swatch_id       text,                                                     -- when kind='color' from palette
    color_hex       text,                                                     -- when kind='color' custom hex
    image_url       text,                                                     -- when kind='image' (Storage URL)
    opacity         double precision not null default 1.0
                                check (opacity >= 0 and opacity <= 1),
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),

    constraint backgrounds_kind_payload check (
        (kind = 'color' and image_url is null
            and (swatch_id is not null or color_hex is not null))
        or (kind = 'image' and image_url is not null
            and swatch_id is null and color_hex is null)
    )
);

drop trigger if exists backgrounds_set_updated_at on public.backgrounds;
create trigger backgrounds_set_updated_at
    before update on public.backgrounds
    for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- shared_groups + members (Phase 1: dormant)
-- -----------------------------------------------------------------------------
-- A named group (e.g., "household") whose members all see notes tagged
-- with the group. Owner is on shared_groups.owner_user_id; members are
-- listed in shared_group_members with their own role + status.
--
-- Membership status lifecycle matches note_collaborators:
--   invited → accepted | declined → (later) left
-- Only the group owner can INSERT new member rows (handled by RLS).

create table if not exists public.shared_groups (
    id              uuid        primary key default gen_random_uuid(),
    owner_user_id   uuid        not null references auth.users(id) on delete cascade,
    name            text        not null,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

drop trigger if exists shared_groups_set_updated_at on public.shared_groups;
create trigger shared_groups_set_updated_at
    before update on public.shared_groups
    for each row execute function public.set_updated_at();

create table if not exists public.shared_group_members (
    group_id     uuid        not null references public.shared_groups(id) on delete cascade,
    user_id      uuid        not null references auth.users(id) on delete cascade,
    role         text        not null default 'editor'
                             check (role in ('editor', 'viewer')),
    status       text        not null default 'invited'
                             check (status in ('invited', 'accepted', 'declined', 'left')),
    invited_at   timestamptz not null default now(),
    responded_at timestamptz,
    primary key (group_id, user_id)
);


-- -----------------------------------------------------------------------------
-- notes
-- -----------------------------------------------------------------------------

create table if not exists public.notes (
    id              uuid            primary key default gen_random_uuid(),
    user_id         uuid            not null references auth.users(id) on delete cascade,

    -- Categorization (FK; type metadata + structured-field schema lives in
    -- `note_types`). NOT NULL — every note belongs to a type. App default
    -- in the editor is the system 'general' type.
    type_id         uuid            not null references public.note_types(id) on delete restrict,

    -- Content shape
    title           text,                       -- nullable; preview falls back to body when empty
    body            jsonb           not null default '[]'::jsonb,
    structured_data jsonb,                      -- shape per the type's `structured_data_schema`

    -- Time / scheduling
    -- Past = journal entry, future = reminder/todo, NULL = evergreen
    -- (running list, no specific time — appears in a separate "Notes"
    -- surface in the UI rather than the dated timeline).
    occurred_at     timestamptz,

    -- Display styling
    title_style     jsonb,                                                   -- {fontId, colorId} | null
    background_id   uuid            references public.backgrounds(id) on delete set null,

    -- State flags (orthogonal axes)
    pinned_at       timestamptz,                                             -- null = not pinned
    completed_at    timestamptz,                                             -- null = not completed
    cancelled_at    timestamptz,                                             -- null = active; non-null = "didn't happen as planned"
    deleted_at      timestamptz,                                             -- null = not deleted (soft delete)

    -- Reschedule audit trail (set on the *new* note when user pushes to a different date)
    rescheduled_from_id uuid        references public.notes(id) on delete set null,

    -- Notifications (Phase F+; reserved column)
    notification_offsets int[],                                              -- minutes-before-occurred_at

    -- Manual reorder (fractional indexing)
    position        double precision,

    -- Group-share scaffold (Phase 1 always null)
    shared_group_id uuid            references public.shared_groups(id) on delete set null,

    -- Audit
    created_at      timestamptz     not null default now(),
    updated_at      timestamptz     not null default now()
);

drop trigger if exists notes_set_updated_at on public.notes;
create trigger notes_set_updated_at
    before update on public.notes
    for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- note_collaborators — unified share + invite (Phase 1: dormant)
-- -----------------------------------------------------------------------------
-- One row per (note, collaborator). `role` controls write access; `status`
-- controls visibility (only 'accepted' rows participate in RLS access).
--
-- UI semantics layered on top of (role, status):
--   - role='viewer', status='accepted'  → "Shared with me" view (read-only)
--   - role='editor', status='accepted'  → main timeline (collaborative co-ownership)
--   - status='invited'                  → recipient's "Invitations" tray
--   - status='declined'                 → audit row, no visibility
--   - status='left'                     → audit row, no visibility (was active, now removed)

create table if not exists public.note_collaborators (
    note_id      uuid        not null references public.notes(id) on delete cascade,
    user_id      uuid        not null references auth.users(id) on delete cascade,
    role         text        not null check (role in ('editor', 'viewer')),
    status       text        not null default 'invited'
                             check (status in ('invited', 'accepted', 'declined', 'left')),
    invited_at   timestamptz not null default now(),
    responded_at timestamptz,
    primary key (note_id, user_id)
);


-- -----------------------------------------------------------------------------
-- Indexes
-- -----------------------------------------------------------------------------

-- notes: main timeline query (user's non-deleted notes, newest-first)
create index if not exists notes_user_occurred_at_idx
    on public.notes (user_id, occurred_at desc nulls last)
    where deleted_at is null;

-- notes: evergreen notes (NULL occurred_at) — separate "Notes" surface
create index if not exists notes_user_evergreen_idx
    on public.notes (user_id, created_at desc)
    where deleted_at is null and occurred_at is null;

-- notes: pinned section query
create index if not exists notes_user_pinned_idx
    on public.notes (user_id, pinned_at desc)
    where deleted_at is null and pinned_at is not null;

-- notes: Cards-mode reorder query (manual position when set, else occurred_at)
create index if not exists notes_user_position_idx
    on public.notes (user_id, position, occurred_at desc)
    where deleted_at is null;

-- notes: Group view query (notes by type)
create index if not exists notes_user_type_idx
    on public.notes (user_id, type_id, occurred_at desc)
    where deleted_at is null;

-- notes: Recently Deleted view
create index if not exists notes_user_deleted_at_idx
    on public.notes (user_id, deleted_at desc)
    where deleted_at is not null;

-- notes: reminder firing query (future events with notifications, not done, not deleted)
create index if not exists notes_notification_due_idx
    on public.notes (occurred_at)
    where notification_offsets is not null
      and deleted_at is null
      and completed_at is null
      and cancelled_at is null;

-- note_collaborators: "what notes have I been invited to / accepted?"
create index if not exists note_collaborators_user_status_idx
    on public.note_collaborators (user_id, status);


-- -----------------------------------------------------------------------------
-- Row-Level Security
-- -----------------------------------------------------------------------------

alter table public.note_types           enable row level security;
alter table public.backgrounds          enable row level security;
alter table public.notes                enable row level security;
alter table public.note_collaborators   enable row level security;
alter table public.shared_groups        enable row level security;
alter table public.shared_group_members enable row level security;


-- note_types: SELECT all system + own; INSERT/UPDATE/DELETE only own custom
drop policy if exists note_types_select on public.note_types;
create policy note_types_select on public.note_types
    for select
    using (created_by_user_id is null or created_by_user_id = auth.uid());

drop policy if exists note_types_insert on public.note_types;
create policy note_types_insert on public.note_types
    for insert
    with check (created_by_user_id = auth.uid());

drop policy if exists note_types_update on public.note_types;
create policy note_types_update on public.note_types
    for update
    using (created_by_user_id = auth.uid());

drop policy if exists note_types_delete on public.note_types;
create policy note_types_delete on public.note_types
    for delete
    using (created_by_user_id = auth.uid());


-- backgrounds: same pattern — SELECT system + own; modify own only
drop policy if exists backgrounds_select on public.backgrounds;
create policy backgrounds_select on public.backgrounds
    for select
    using (user_id is null or user_id = auth.uid());

drop policy if exists backgrounds_insert on public.backgrounds;
create policy backgrounds_insert on public.backgrounds
    for insert
    with check (user_id = auth.uid());

drop policy if exists backgrounds_update on public.backgrounds;
create policy backgrounds_update on public.backgrounds
    for update
    using (user_id = auth.uid());

drop policy if exists backgrounds_delete on public.backgrounds;
create policy backgrounds_delete on public.backgrounds
    for delete
    using (user_id = auth.uid());


-- notes: SELECT — owner OR accepted per-note collaborator OR accepted shared-group member OR group owner
drop policy if exists notes_select on public.notes;
create policy notes_select on public.notes
    for select
    using (
        user_id = auth.uid()
        or exists (
            select 1 from public.note_collaborators nc
             where nc.note_id  = notes.id
               and nc.user_id  = auth.uid()
               and nc.status   = 'accepted'
        )
        or exists (
            select 1 from public.shared_group_members sgm
             where sgm.group_id = notes.shared_group_id
               and sgm.user_id  = auth.uid()
               and sgm.status   = 'accepted'
        )
        or exists (
            select 1 from public.shared_groups sg
             where sg.id = notes.shared_group_id and sg.owner_user_id = auth.uid()
        )
    );

drop policy if exists notes_insert on public.notes;
create policy notes_insert on public.notes
    for insert
    with check (user_id = auth.uid());

-- UPDATE: owner OR per-note editor (accepted) OR group editor (accepted) OR group owner
drop policy if exists notes_update on public.notes;
create policy notes_update on public.notes
    for update
    using (
        user_id = auth.uid()
        or exists (
            select 1 from public.note_collaborators nc
             where nc.note_id = notes.id
               and nc.user_id = auth.uid()
               and nc.status  = 'accepted'
               and nc.role    = 'editor'
        )
        or exists (
            select 1 from public.shared_group_members sgm
             where sgm.group_id = notes.shared_group_id
               and sgm.user_id  = auth.uid()
               and sgm.status   = 'accepted'
               and sgm.role     = 'editor'
        )
        or exists (
            select 1 from public.shared_groups sg
             where sg.id = notes.shared_group_id and sg.owner_user_id = auth.uid()
        )
    );

-- DELETE: only the owner can hard-delete; everyone soft-deletes via UPDATE
drop policy if exists notes_delete on public.notes;
create policy notes_delete on public.notes
    for delete
    using (user_id = auth.uid());


-- note_collaborators: owner manages; recipient sees + responds to own row
drop policy if exists note_collaborators_select on public.note_collaborators;
create policy note_collaborators_select on public.note_collaborators
    for select
    using (
        user_id = auth.uid()
        or exists (
            select 1 from public.notes n
             where n.id = note_id and n.user_id = auth.uid()
        )
    );

drop policy if exists note_collaborators_insert on public.note_collaborators;
create policy note_collaborators_insert on public.note_collaborators
    for insert
    with check (
        exists (
            select 1 from public.notes n
             where n.id = note_id and n.user_id = auth.uid()
        )
    );

-- UPDATE allows the recipient to flip status (invited→accepted/declined/left),
-- and the note owner to change role.
drop policy if exists note_collaborators_update on public.note_collaborators;
create policy note_collaborators_update on public.note_collaborators
    for update
    using (
        user_id = auth.uid()
        or exists (
            select 1 from public.notes n
             where n.id = note_id and n.user_id = auth.uid()
        )
    );

drop policy if exists note_collaborators_delete on public.note_collaborators;
create policy note_collaborators_delete on public.note_collaborators
    for delete
    using (
        user_id = auth.uid()
        or exists (
            select 1 from public.notes n
             where n.id = note_id and n.user_id = auth.uid()
        )
    );


-- shared_groups: owner manages; accepted members read groups they belong to
drop policy if exists shared_groups_select on public.shared_groups;
create policy shared_groups_select on public.shared_groups
    for select
    using (
        owner_user_id = auth.uid()
        or exists (
            select 1 from public.shared_group_members sgm
             where sgm.group_id = id
               and sgm.user_id  = auth.uid()
               and sgm.status   = 'accepted'
        )
    );

drop policy if exists shared_groups_insert on public.shared_groups;
create policy shared_groups_insert on public.shared_groups
    for insert
    with check (owner_user_id = auth.uid());

drop policy if exists shared_groups_update on public.shared_groups;
create policy shared_groups_update on public.shared_groups
    for update
    using (owner_user_id = auth.uid());

drop policy if exists shared_groups_delete on public.shared_groups;
create policy shared_groups_delete on public.shared_groups
    for delete
    using (owner_user_id = auth.uid());


-- shared_group_members: ONLY the group owner can INSERT (Phase 1 rule).
-- Members can read their own row + see other members of groups they're in.
-- Members can UPDATE their own row to flip status (accept/decline/leave).
-- Members can DELETE themselves; owners can remove members.
drop policy if exists shared_group_members_select on public.shared_group_members;
create policy shared_group_members_select on public.shared_group_members
    for select
    using (
        user_id = auth.uid()
        or exists (
            select 1 from public.shared_groups sg
             where sg.id = group_id and sg.owner_user_id = auth.uid()
        )
        or exists (
            select 1 from public.shared_group_members peer
             where peer.group_id = group_id
               and peer.user_id  = auth.uid()
               and peer.status   = 'accepted'
        )
    );

drop policy if exists shared_group_members_insert on public.shared_group_members;
create policy shared_group_members_insert on public.shared_group_members
    for insert
    with check (
        exists (
            select 1 from public.shared_groups sg
             where sg.id = group_id and sg.owner_user_id = auth.uid()
        )
    );

drop policy if exists shared_group_members_update on public.shared_group_members;
create policy shared_group_members_update on public.shared_group_members
    for update
    using (
        user_id = auth.uid()  -- recipient: flip own status
        or exists (
            select 1 from public.shared_groups sg
             where sg.id = group_id and sg.owner_user_id = auth.uid()  -- owner: change role
        )
    );

drop policy if exists shared_group_members_delete on public.shared_group_members;
create policy shared_group_members_delete on public.shared_group_members
    for delete
    using (
        user_id = auth.uid()  -- members can leave a group themselves
        or exists (
            select 1 from public.shared_groups sg
             where sg.id = group_id and sg.owner_user_id = auth.uid()  -- owners can remove
        )
    );


-- =============================================================================
-- Seed: system note types
-- =============================================================================
-- Slugs are stable identifiers used by the iOS client. Color hexes are the
-- design-system pigments (`design/claude-design-system/colors_and_type.css`,
-- `--dc-*` variables). SF Symbol icons match `NoteType.systemImage` in the
-- iOS code. `structured_data_schema` starts empty — field schemas can be
-- populated later via UPDATE (or the future admin panel) without a migration
-- since the column is jsonb.

insert into public.note_types (slug, display_name, color_hex, icon, structured_data_schema)
values
    ('general',  'General',  '#8B8680', 'note.text',            '{"fields": []}'::jsonb),
    ('workout',  'Workout',  '#B05B3B', 'dumbbell',             '{"fields": []}'::jsonb),
    ('meal',     'Meal',     '#C9893A', 'fork.knife',           '{"fields": []}'::jsonb),
    ('sleep',    'Sleep',    '#3E4A64', 'moon',                 '{"fields": []}'::jsonb),
    ('mood',     'Mood',     '#8B6B85', 'heart',                '{"fields": []}'::jsonb),
    ('activity', 'Activity', '#7B8B52', 'figure.walk',          '{"fields": []}'::jsonb),
    ('media',    'Media',    '#CBCADA', 'photo.on.rectangle',   '{"fields": []}'::jsonb)
on conflict do nothing;


-- =============================================================================
-- Seed: system color backgrounds
-- =============================================================================
-- A starter set of system-level color backgrounds. swatch_id values are real
-- ids from `apps/ios/DailyCadence/DailyCadence/Resources/palettes.json` —
-- the iOS client resolves swatch_id → Color via PaletteRepository at render
-- time. Future system backgrounds can be added via INSERT without migration.

insert into public.backgrounds (user_id, label, kind, swatch_id, opacity)
values
    (null, 'Linen',     'color', 'neutral.linen',     1.0),
    (null, 'Sand',      'color', 'neutral.sand',      1.0),
    (null, 'Taupe',     'color', 'neutral.taupe',     1.0),
    (null, 'Mint',      'color', 'pastel.mint',       1.0),
    (null, 'Sky',       'color', 'pastel.sky',        1.0),
    (null, 'Lavender',  'color', 'pastel.lavender',   1.0),
    (null, 'Lilac',     'color', 'pastel.lilac',      1.0)
on conflict do nothing;
