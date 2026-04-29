// Supabase Edge Function — `delete-account`
//
// Apple Review Guideline 5.1.1(v) compliance: in-app account deletion that
// removes the auth user AND all their data, including Storage objects.
//
// Flow:
//   1. Verify the caller's JWT against `auth.users` (only the user themselves
//      can delete their account; service-role can't be hijacked from outside).
//   2. List + delete every Storage object under `{user_id}/` in both
//      `note-media` and `note-backgrounds` buckets — uses the SDK's `.remove()`
//      which handles both metadata and the underlying S3 blob (direct
//      `DELETE FROM storage.objects` would only remove metadata).
//   3. `auth.admin.deleteUser(id)` — cascades the SQL data via FK ON DELETE
//      CASCADE on `notes`, `backgrounds`, `note_types.created_by_user_id`,
//      `shared_groups.owner_user_id`, etc.
//
// Called from iOS via `AppSupabase.client.functions.invoke("delete-account")`.
// On success the function returns `{ ok: true }`; the SDK then emits a
// `.userDeleted` auth event which `AuthStore.bootstrap()` routes back to a
// no-user state, and RootView swaps to OnboardingScreen.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BUCKETS = ["note-media", "note-backgrounds"] as const;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  // Resolve the caller via their JWT. This is the only way we know *who*
  // is asking to be deleted — service-role bypasses RLS but doesn't tell
  // us anything about the caller.
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    return json({ error: "Invalid session" }, 401);
  }
  const userId = userData.user.id;

  // Service role for the actual destructive ops.
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1. Storage cleanup. Pagination guards against the (unlikely) case of
  //    a user with > 1000 files in a single bucket.
  const removed: Record<string, number> = {};
  for (const bucket of BUCKETS) {
    removed[bucket] = await deleteAllFilesUnder(adminClient, bucket, userId);
  }

  // 2. Auth user delete — cascades notes, backgrounds, custom note_types, etc.
  const { error: deleteError } = await adminClient.auth.admin.deleteUser(userId);
  if (deleteError) {
    return json({
      error: `auth delete failed: ${deleteError.message}`,
      removed,
    }, 500);
  }

  return json({ ok: true, removed });
});

// deno-lint-ignore no-explicit-any
async function deleteAllFilesUnder(client: any, bucket: string, userId: string): Promise<number> {
  let total = 0;
  // Page through in 1000-file chunks. Supabase Storage `list` is paginated;
  // we keep listing until we get fewer than `limit` results (= last page).
  // After each batch we delete what we just listed; the next list call sees
  // the bucket as empty under this prefix.
  while (true) {
    const { data: files, error: listError } = await client.storage
      .from(bucket)
      .list(userId, { limit: 1000 });
    if (listError) {
      console.warn(`list ${bucket}: ${listError.message}`);
      return total;
    }
    if (!files || files.length === 0) return total;

    const paths = files.map((f: { name: string }) => `${userId}/${f.name}`);
    const { error: removeError } = await client.storage.from(bucket).remove(paths);
    if (removeError) {
      console.warn(`remove ${bucket}: ${removeError.message}`);
      return total;
    }
    total += files.length;
    if (files.length < 1000) return total;
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
