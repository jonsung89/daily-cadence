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
        return SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }()
}
