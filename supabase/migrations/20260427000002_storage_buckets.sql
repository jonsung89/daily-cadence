-- =============================================================================
-- Migration 002: storage_buckets
-- =============================================================================
-- Two private Supabase Storage buckets for binary content referenced by
-- `notes.body` and `notes.background`. The `notes` table itself never holds
-- bytes — it stores URLs into these buckets.
--
-- Path convention: `{user_id}/{filename}` so the per-user RLS policies can
-- check the first path segment against `auth.uid()`. Filenames are
-- app-generated UUIDs to avoid conflicts.
--
-- Buckets are *private* (`public := false`). The iOS client requests signed
-- URLs from Supabase to render images; signed URLs expire and aren't
-- guessable. Phase F+ may add a CDN cache layer; doesn't affect schema.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Buckets
-- -----------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('note-media', 'note-media', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('note-backgrounds', 'note-backgrounds', false)
on conflict (id) do nothing;


-- -----------------------------------------------------------------------------
-- RLS policies — per-user folder isolation
-- -----------------------------------------------------------------------------
-- File path expected as `{user_id}/{filename}`. `storage.foldername(name)[1]`
-- extracts the first path segment.

-- note-media
drop policy if exists "note-media own folder insert" on storage.objects;
create policy "note-media own folder insert"
    on storage.objects for insert
    with check (
        bucket_id = 'note-media'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "note-media own folder read" on storage.objects;
create policy "note-media own folder read"
    on storage.objects for select
    using (
        bucket_id = 'note-media'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "note-media own folder delete" on storage.objects;
create policy "note-media own folder delete"
    on storage.objects for delete
    using (
        bucket_id = 'note-media'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "note-media own folder update" on storage.objects;
create policy "note-media own folder update"
    on storage.objects for update
    using (
        bucket_id = 'note-media'
        and (storage.foldername(name))[1] = auth.uid()::text
    );


-- note-backgrounds
drop policy if exists "note-backgrounds own folder insert" on storage.objects;
create policy "note-backgrounds own folder insert"
    on storage.objects for insert
    with check (
        bucket_id = 'note-backgrounds'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "note-backgrounds own folder read" on storage.objects;
create policy "note-backgrounds own folder read"
    on storage.objects for select
    using (
        bucket_id = 'note-backgrounds'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "note-backgrounds own folder delete" on storage.objects;
create policy "note-backgrounds own folder delete"
    on storage.objects for delete
    using (
        bucket_id = 'note-backgrounds'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "note-backgrounds own folder update" on storage.objects;
create policy "note-backgrounds own folder update"
    on storage.objects for update
    using (
        bucket_id = 'note-backgrounds'
        and (storage.foldername(name))[1] = auth.uid()::text
    );
