import Foundation
import OSLog
import Supabase

/// Manages the user's Supabase auth session for the app's lifetime.
///
/// Bootstrap flow (under `emitLocalSessionAsInitialSession: true`, set in
/// `AppSupabase`):
/// 1. Subscribe to `authStateChanges` — its first emit is `.initialSession`,
///    carrying whatever the SDK has in Keychain. The session may be expired:
///    the SDK no longer refreshes before emitting, and we have to check
///    `session.isExpired` ourselves.
/// 2. Branches:
///    - Valid session → apply, mark ready.
///    - Expired session → wait. The SDK's auto-refresh kicks in and fires
///      `.tokenRefreshed` (success) or `.signedOut` (refresh failed).
///    - No session → mark ready with no user. RootView shows
///      `OnboardingScreen`; the user picks a provider and we exchange.
/// 3. `isReady = true` once we either have a usable session or know we
///    don't (so views can stop showing a loading state and either render
///    the timeline or the onboarding screen).
///
/// Existing anonymous sessions from the dev-mode era still load as valid
/// initial sessions — we don't force a sign-out. The user can choose to
/// sign in with Apple/Google whenever; from that point forward, the
/// session is no longer anonymous. (Migrating an anon user's notes onto a
/// fresh Apple/Google account is a separate concern not solved here.)
@Observable
final class AuthStore {
    static let shared = AuthStore()

    private(set) var currentUserId: UUID?
    private(set) var email: String?
    /// First name pulled from the active session's user metadata
    /// (`raw_user_meta_data->>'first_name'`). Pre-populated by Apple
    /// (when the user shares their name on first sign-in) or Google
    /// (`given_name`); editable through `updateProfile(...)` and
    /// surfaced in the Profile onboarding page.
    private(set) var firstName: String?
    /// Last name from session metadata (`last_name` / `family_name`).
    private(set) var lastName: String?
    /// Bucket-relative path of the user's profile image, e.g.
    /// `{user_id}/{uuid}.jpg`. Lives in `profile_image_path` on the
    /// session metadata. The actual displayable URL is fetched on
    /// demand via `MediaStorageProvider.profileImages.signedURL(...)`
    /// since the bucket is private.
    private(set) var profileImagePath: String?
    private(set) var isReady = false
    private(set) var lastError: String?

    /// True when at least one of `firstName` / `lastName` is non-empty.
    /// Used by `RootView`'s onboarding gate as a cross-device safety
    /// net: `hasCompletedOnboarding` is device-local
    /// (`UserDefaults`), so a returning user on a new device would
    /// otherwise see onboarding again. Names round-trip through
    /// `auth.users.raw_user_meta_data` (server-side), so checking
    /// them here gives us a reliable "this user has been set up"
    /// signal regardless of which device they're on.
    var hasName: Bool {
        let first = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !first.isEmpty || !last.isEmpty
    }

    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "AuthStore")
    private var listenerTask: Task<Void, Never>?

    private init() {
        listenerTask = Task { await self.bootstrap() }
    }

    deinit {
        listenerTask?.cancel()
    }

    private func bootstrap() async {
        for await (event, session) in AppSupabase.client.auth.authStateChanges {
            log.debug("auth event: \(String(describing: event)) user=\(session?.user.id.uuidString ?? "nil") expired=\(session?.isExpired ?? false)")
            switch event {
            case .initialSession:
                if let session, !session.isExpired {
                    apply(session)
                    isReady = true
                } else if session != nil {
                    // Expired stored session — don't apply. The SDK's
                    // auto-refresh will fire `.tokenRefreshed` (success)
                    // or `.signedOut` (refresh-token also dead). Stay in
                    // the not-ready state until that resolves.
                    log.info("Stored session expired — waiting for refresh")
                } else {
                    // Nothing in Keychain — show onboarding.
                    currentUserId = nil
                    email = nil
                    isReady = true
                }
            case .signedIn, .tokenRefreshed, .userUpdated:
                if let session { apply(session) }
                isReady = true
            case .signedOut, .userDeleted:
                let hadUser = currentUserId != nil
                currentUserId = nil
                email = nil
                isReady = true
                // Wipe singleton caches so user A's notes/week-dots
                // don't bleed into user B's session when the user signs
                // back in without quitting the app. Reset BEFORE any
                // view's .task(id:) re-evaluates — doing it here in the
                // auth event handler avoids the race.
                if hadUser {
                    TimelineStore.shared.resetForUserChange()
                    WeekStripStore.shared.resetForUserChange()
                    Task { @MainActor in ProfileImageCache.shared.invalidate() }
                }
            default:
                break
            }
        }
    }

    /// Exchanges an Apple ID token for a Supabase session.
    ///
    /// The caller (`OnboardingScreen`) generates a fresh `AppleSignInNonce`
    /// before invoking `SignInWithAppleButton`, sends the hashed half to
    /// Apple in the authorization request, and forwards the raw half here.
    /// Supabase re-hashes and matches against the `nonce` claim inside the
    /// ID token, which proves the token was minted in response to *our*
    /// request and isn't a replay.
    ///
    /// On success the SDK emits `.signedIn` through `authStateChanges`,
    /// `apply(_:)` updates `currentUserId` + `email`, and RootView swaps
    /// the onboarding screen for the timeline. On failure we surface the
    /// error to the caller for UI display *and* mirror it on `lastError`.
    func signInWithApple(idToken: String, rawNonce: String) async throws {
        do {
            _ = try await AppSupabase.client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: rawNonce
                )
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("signInWithApple failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Exchanges a Google sign-in for a Supabase session via the OAuth
    /// authorization-code flow.
    ///
    /// The Supabase SDK wraps `ASWebAuthenticationSession` for us — it
    /// builds the `/authorize?provider=google` URL, presents the system
    /// browser sheet, listens for the `com.jonsung.dailycadence://...`
    /// redirect, and exchanges the returned code for a session. The
    /// resulting `.signedIn` event flows through `authStateChanges` and
    /// `apply(_:)` updates `currentUserId` + `email`.
    ///
    /// User-cancelled is surfaced as `ASWebAuthenticationSessionError`;
    /// the caller (`OnboardingScreen`) silences it.
    func signInWithGoogle() async throws {
        do {
            let redirectURL = URL(string: "com.jonsung.dailycadence://login-callback")!
            _ = try await AppSupabase.client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: redirectURL,
                // `prompt=select_account` forces Google to show its account
                // chooser even when a session is cached in the in-app
                // browser. Without it, Google silently reuses whichever
                // Google account the user is currently signed into in
                // Safari, which surprises users on shared devices and
                // makes "sign in as someone else" impossible.
                queryParams: [(name: "prompt", value: "select_account")]
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("signInWithGoogle failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Clears the current Supabase session. Emits `.signedOut` through
    /// `authStateChanges`, which our handler routes back to a no-user
    /// state so RootView shows the onboarding screen again.
    func signOut() async throws {
        do {
            try await AppSupabase.client.auth.signOut()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("signOut failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Deletes the current user's account permanently. Apple Review
    /// Guideline 5.1.1(v) requires this be in-app and remove ALL the
    /// developer's collected data — for us that means auth user + SQL
    /// data (notes, backgrounds, etc. via FK CASCADE) + Storage objects
    /// in `note-media` and `note-backgrounds`.
    ///
    /// Direct SQL `DELETE` on `storage.objects` would only remove the
    /// metadata row, leaving the underlying S3 blob orphaned, so the
    /// cleanup is delegated to a Supabase Edge Function
    /// (`supabase/functions/delete-account`) running with service-role
    /// access. The function uses the Storage SDK's `.remove()` to clean
    /// blob + metadata together, then `auth.admin.deleteUser(uid)`.
    ///
    /// On success Supabase fires `.userDeleted` through
    /// `authStateChanges`; our handler clears `currentUserId` and the
    /// RootView gate swaps to `OnboardingScreen`.
    func deleteAccount() async throws {
        do {
            _ = try await AppSupabase.client.functions.invoke("delete-account")
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("deleteAccount failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Persists first/last name to the active user's
    /// `raw_user_meta_data`. We use the auth metadata (vs. a separate
    /// `profiles` table) because Apple/Google already populate keys
    /// like `first_name`/`given_name` here on sign-in; reading + writing
    /// the same JSONB keeps Phase 1 simple. A future `profiles` table
    /// can mirror this when we add structured profile fields beyond
    /// names (bio, timezone, etc.).
    /// Persists the profile image path (bucket-relative) to the
    /// active user's `raw_user_meta_data`. Pass `nil` to clear it
    /// (user removed their photo). The Storage object itself isn't
    /// touched here; orphan cleanup happens through pg_cron later
    /// (same lifecycle as background images).
    func updateProfileImagePath(_ path: String?) async throws {
        do {
            let attrs = UserAttributes(
                data: ["profile_image_path": path.map { .string($0) } ?? .null]
            )
            _ = try await AppSupabase.client.auth.update(user: attrs)
            self.profileImagePath = path
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("updateProfileImagePath failed: \(error.localizedDescription)")
            throw error
        }
    }

    func updateProfile(firstName: String, lastName: String) async throws {
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let attrs = UserAttributes(
                data: [
                    "first_name": .string(trimmedFirst),
                    "last_name": .string(trimmedLast),
                ]
            )
            _ = try await AppSupabase.client.auth.update(user: attrs)
            // Optimistic local update — `.userUpdated` will reaffirm.
            self.firstName = trimmedFirst.isEmpty ? nil : trimmedFirst
            self.lastName = trimmedLast.isEmpty ? nil : trimmedLast
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("updateProfile failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func apply(_ session: Session) {
        // Defensive: if a token refresh somehow swapped users (or we
        // missed an intervening .signedOut), wipe the dependent
        // singleton caches before applying so we don't render user A's
        // data as user B. The hadUser=nil → newUser flow doesn't need
        // this — sign-in from onboarding already started from a clean
        // slate (the .signedOut handler above ran when sign-out
        // happened).
        if let prev = currentUserId, prev != session.user.id {
            TimelineStore.shared.resetForUserChange()
            WeekStripStore.shared.resetForUserChange()
            Task { @MainActor in ProfileImageCache.shared.invalidate() }
        }
        currentUserId = session.user.id
        email = session.user.email
        // Read names out of the user metadata JSONB. Apple/Google
        // populate slightly different keys (`first_name` vs
        // `given_name`); we honor both so a freshly-signed-in user
        // sees their name pre-filled regardless of provider.
        let meta = session.user.userMetadata
        firstName = stringFromMeta(meta, keys: ["first_name", "given_name"])
        lastName = stringFromMeta(meta, keys: ["last_name", "family_name"])
        profileImagePath = stringFromMeta(meta, keys: ["profile_image_path"])
        lastError = nil
        log.info("Active session for user \(session.user.id)")
    }

    private func stringFromMeta(_ meta: [String: AnyJSON], keys: [String]) -> String? {
        for key in keys {
            if case let .string(value)? = meta[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
