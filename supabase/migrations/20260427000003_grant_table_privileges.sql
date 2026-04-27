-- =============================================================================
-- 20260427000003 — grant table privileges to anon + authenticated roles
-- =============================================================================
-- Phase F.0.2 caught this: the iOS client (running as `authenticated` after
-- anon sign-in) hit "permission denied for table note_types" on launch.
--
-- RLS policies don't grant access — PostgreSQL checks GRANT first, and only
-- if the role has the privilege does RLS get to evaluate row-level rules.
-- Supabase's default privilege defaults grant new tables to anon + auth, but
-- something in this project's setup didn't pick those defaults up for the
-- tables created in 20260427000001. Explicit grants here close the gap.
--
-- Principle of least privilege:
--   - `note_types`, `backgrounds`: SELECT (read), INSERT (user-created rows
--     where created_by_user_id = auth.uid()), UPDATE/DELETE (own custom rows).
--     RLS policies in _001 enforce ownership.
--   - `notes`: full CRUD (RLS scopes to auth.uid()).
--   - `note_collaborators`, `shared_groups`, `shared_group_members`: full CRUD
--     so the future sharing UI works without another grants pass; RLS policies
--     in _001 enforce role + status semantics.
--
-- The `anon` role gets nothing — anonymous users in this app go through anon
-- sign-in (`auth.signInAnonymously()`) which produces an `authenticated`
-- session with a real `auth.uid()`. There's no use case for unauthenticated
-- table reads.
--
-- Re-running is safe: GRANT is idempotent.
-- -----------------------------------------------------------------------------

grant select, insert, update, delete on public.note_types           to authenticated;
grant select, insert, update, delete on public.backgrounds          to authenticated;
grant select, insert, update, delete on public.notes                to authenticated;
grant select, insert, update, delete on public.note_collaborators   to authenticated;
grant select, insert, update, delete on public.shared_groups        to authenticated;
grant select, insert, update, delete on public.shared_group_members to authenticated;

-- Sequences are auto-created for any `serial`/`bigserial` columns. None of
-- our tables use them today (uuid PKs), but if a future migration adds one,
-- it'll need its own grant.
