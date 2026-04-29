-- =============================================================================
-- Migration 003: profile_images_bucket
-- =============================================================================
-- Private Supabase Storage bucket for user profile photos. Per-user folder
-- isolation enforced by RLS — users can only read/write paths under their
-- own auth.uid()/ prefix.
--
-- Path convention: `{user_id}/{filename}` (matches existing note-media and
-- note-backgrounds buckets).
--
-- The iOS client reads the path from auth.users.raw_user_meta_data
-- ('profile_image_path') and fetches a short-lived signed URL via the
-- MediaStorage abstraction. Bucket is private; signed URLs handle access.
-- =============================================================================

insert into storage.buckets (id, name, public)
values ('profile-images', 'profile-images', false)
on conflict (id) do nothing;

-- Per-user folder isolation. `storage.foldername(name)[1]` returns the first
-- path segment (the user_id prefix). Allow only when it matches the caller's
-- auth.uid().

drop policy if exists "profile-images own folder insert" on storage.objects;
create policy "profile-images own folder insert"
    on storage.objects for insert
    with check (
        bucket_id = 'profile-images'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

drop policy if exists "profile-images own folder select" on storage.objects;
create policy "profile-images own folder select"
    on storage.objects for select
    using (
        bucket_id = 'profile-images'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

drop policy if exists "profile-images own folder update" on storage.objects;
create policy "profile-images own folder update"
    on storage.objects for update
    using (
        bucket_id = 'profile-images'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

drop policy if exists "profile-images own folder delete" on storage.objects;
create policy "profile-images own folder delete"
    on storage.objects for delete
    using (
        bucket_id = 'profile-images'
        and auth.uid()::text = (storage.foldername(name))[1]
    );
