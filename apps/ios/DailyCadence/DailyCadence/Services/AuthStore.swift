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
///    - No session → call `signInAnonymously()`; the resulting `.signedIn`
///      event flows back through the same stream.
/// 3. Set `isReady = true` once we either have a usable session or know we
///    failed, so consumers (a future `NotesRepository`) can stop waiting.
///
/// Anonymous auth is the Phase F dev mode while Apple Developer enrollment
/// finishes review. RLS works the same — the user gets a real `auth.uid()`.
/// When Apple/Google providers come online we'll link the existing
/// anonymous identity rather than start fresh, so notes don't disappear.
@Observable
final class AuthStore {
    static let shared = AuthStore()

    private(set) var currentUserId: UUID?
    private(set) var isReady = false
    private(set) var lastError: String?

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
                    // Nothing in Keychain — start a fresh anon session.
                    await signInAnonymously()
                }
            case .signedIn, .tokenRefreshed:
                if let session { apply(session) }
                isReady = true
            case .signedOut, .userDeleted:
                // We landed here either because refresh failed (expired
                // session at boot) or the server tombstoned the anon
                // user. In dev mode, get a fresh anon session so the
                // app stays usable.
                currentUserId = nil
                await signInAnonymously()
            default:
                break
            }
        }
    }

    private func signInAnonymously() async {
        do {
            _ = try await AppSupabase.client.auth.signInAnonymously()
            // The resulting `.signedIn` event arrives on the stream and
            // flows through `apply(_:)` — no need to handle the return.
        } catch {
            lastError = error.localizedDescription
            isReady = true
            log.error("signInAnonymously failed: \(error.localizedDescription)")
        }
    }

    private func apply(_ session: Session) {
        currentUserId = session.user.id
        lastError = nil
        log.info("Active session for user \(session.user.id)")
    }
}
