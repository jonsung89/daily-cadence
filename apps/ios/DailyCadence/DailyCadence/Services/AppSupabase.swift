import Foundation
import Supabase

enum AppSupabase {
    static let client: SupabaseClient = {
        let info = Bundle.main.infoDictionary
        guard
            let urlString = info?["SupabaseURL"] as? String,
            !urlString.isEmpty,
            let url = URL(string: urlString),
            let anonKey = info?["SupabaseAnonKey"] as? String,
            !anonKey.isEmpty
        else {
            fatalError("""
                Supabase config missing. Copy Config.example.xcconfig to Config.xcconfig \
                in apps/ios/DailyCadence/, fill in SUPABASE_URL + SUPABASE_ANON_KEY, then rebuild.
                """)
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            // Opt-in to the next-major-version semantics for `.initialSession`:
            // emit whatever's in Keychain immediately, possibly expired, and let
            // a follow-up `.tokenRefreshed` (or `.signedOut`) settle it. The
            // legacy default refreshes before emitting, which masks expired
            // sessions. AuthStore checks `session.isExpired` to handle both.
            options: .init(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }()
}
