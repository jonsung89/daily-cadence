-- =============================================================================
-- 20260427000004 — fix infinite-recursion RLS policies
-- =============================================================================
-- Phase F.0.2 caught this on first `select * from notes` from the iOS client:
--
--     load failed: infinite recursion detected in policy for relation "notes"
--
-- Two policies in 20260427000001 cross-reference each other:
--
--   - `notes_select`               does EXISTS(SELECT ... FROM note_collaborators ...)
--   - `note_collaborators_select`  does EXISTS(SELECT ... FROM notes ...)
--
-- Postgres detects the cycle at query-plan time, even when the joined tables
-- are empty. Same recursion exists between `shared_group_members_select` and
-- (transitively) `notes` via `shared_group_id`.
--
-- The standard Postgres / Supabase fix is `SECURITY DEFINER` helper functions:
-- they execute as the function owner (`postgres` here, which has BYPASSRLS),
-- so the SELECTs inside the function don't re-evaluate the calling table's
-- RLS policies. The cycle breaks because the inner check is "outside" RLS.
--
-- Helpers below are STABLE (same inputs, same result within a statement) so
-- the planner can hoist + cache them per-row. `SET search_path = public`
-- locks the schema resolution against future search_path manipulation.
--
-- Re-running is safe: `create or replace function`, `drop policy if exists`,
-- and `grant ... if not exists`-style idempotent grants.
-- -----------------------------------------------------------------------------


-- -----------------------------------------------------------------------------
-- Helper functions
-- -----------------------------------------------------------------------------

-- Is the caller the owner of `p_note_id`?
create or replace function public.auth_is_note_owner(p_note_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.notes
         where id = p_note_id and user_id = auth.uid()
    );
$$;

-- Is the caller an accepted per-note collaborator on `p_note_id`?
-- `p_min_role` lets callers ask "any role" (pass NULL) or "editor only" (pass 'editor').
create or replace function public.auth_is_note_collaborator(
    p_note_id uuid,
    p_min_role text default null
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.note_collaborators
         where note_id = p_note_id
           and user_id = auth.uid()
           and status  = 'accepted'
           and (p_min_role is null or role = p_min_role)
    );
$$;

-- Is the caller an accepted member of `p_group_id`?
-- `p_min_role` mirrors `auth_is_note_collaborator`.
create or replace function public.auth_is_group_member(
    p_group_id uuid,
    p_min_role text default null
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.shared_group_members
         where group_id = p_group_id
           and user_id  = auth.uid()
           and status   = 'accepted'
           and (p_min_role is null or role = p_min_role)
    );
$$;

-- Is the caller the owner of `p_group_id`?
create or replace function public.auth_is_group_owner(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.shared_groups
         where id = p_group_id and owner_user_id = auth.uid()
    );
$$;

grant execute on function public.auth_is_note_owner(uuid)             to authenticated;
grant execute on function public.auth_is_note_collaborator(uuid, text) to authenticated;
grant execute on function public.auth_is_group_member(uuid, text)      to authenticated;
grant execute on function public.auth_is_group_owner(uuid)             to authenticated;


-- -----------------------------------------------------------------------------
-- Rebuild affected policies using the helpers
-- -----------------------------------------------------------------------------

-- notes: SELECT — owner OR per-note collaborator (any role) OR group member OR group owner
drop policy if exists notes_select on public.notes;
create policy notes_select on public.notes
    for select
    using (
        user_id = auth.uid()
        or public.auth_is_note_collaborator(id)
        or (shared_group_id is not null and public.auth_is_group_member(shared_group_id))
        or (shared_group_id is not null and public.auth_is_group_owner(shared_group_id))
    );

-- notes: UPDATE — owner OR per-note editor OR group editor OR group owner
drop policy if exists notes_update on public.notes;
create policy notes_update on public.notes
    for update
    using (
        user_id = auth.uid()
        or public.auth_is_note_collaborator(id, 'editor')
        or (shared_group_id is not null and public.auth_is_group_member(shared_group_id, 'editor'))
        or (shared_group_id is not null and public.auth_is_group_owner(shared_group_id))
    );


-- note_collaborators: SELECT — own row OR you own the note
drop policy if exists note_collaborators_select on public.note_collaborators;
create policy note_collaborators_select on public.note_collaborators
    for select
    using (
        user_id = auth.uid()
        or public.auth_is_note_owner(note_id)
    );

drop policy if exists note_collaborators_insert on public.note_collaborators;
create policy note_collaborators_insert on public.note_collaborators
    for insert
    with check (public.auth_is_note_owner(note_id));

drop policy if exists note_collaborators_update on public.note_collaborators;
create policy note_collaborators_update on public.note_collaborators
    for update
    using (
        user_id = auth.uid()
        or public.auth_is_note_owner(note_id)
    );

drop policy if exists note_collaborators_delete on public.note_collaborators;
create policy note_collaborators_delete on public.note_collaborators
    for delete
    using (
        user_id = auth.uid()
        or public.auth_is_note_owner(note_id)
    );


-- shared_groups: SELECT — owner OR accepted member
drop policy if exists shared_groups_select on public.shared_groups;
create policy shared_groups_select on public.shared_groups
    for select
    using (
        owner_user_id = auth.uid()
        or public.auth_is_group_member(id)
    );


-- shared_group_members: SELECT — own row OR group owner OR fellow accepted member
drop policy if exists shared_group_members_select on public.shared_group_members;
create policy shared_group_members_select on public.shared_group_members
    for select
    using (
        user_id = auth.uid()
        or public.auth_is_group_owner(group_id)
        or public.auth_is_group_member(group_id)
    );

drop policy if exists shared_group_members_insert on public.shared_group_members;
create policy shared_group_members_insert on public.shared_group_members
    for insert
    with check (public.auth_is_group_owner(group_id));

drop policy if exists shared_group_members_update on public.shared_group_members;
create policy shared_group_members_update on public.shared_group_members
    for update
    using (
        user_id = auth.uid()
        or public.auth_is_group_owner(group_id)
    );

drop policy if exists shared_group_members_delete on public.shared_group_members;
create policy shared_group_members_delete on public.shared_group_members
    for delete
    using (
        user_id = auth.uid()
        or public.auth_is_group_owner(group_id)
    );
