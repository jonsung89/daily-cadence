import Foundation
import Observation
import OSLog

/// Holds the user's current primary-color selection and persists it across
/// launches.
///
/// Views read `ThemeStore.shared.primary` through the dynamic tokens in
/// `Color+Sage.swift` (`Color.DS.sage` / `sageDeep` / `sageSoft`); the
/// Observation framework tracks those reads so any view consuming the
/// primary color automatically re-renders when `select(_:)` fires.
///
/// **Persistence**: `UserDefaults` via a single key holding the swatch id.
/// The id is resolved against `PrimaryPaletteRepository.shared` on launch —
/// if the stored id has been removed from the palette (e.g. after a remote
/// config update), the store gracefully falls back to the default swatch.
///
/// **Supabase sync** is intentionally deferred to Phase F: `UserDefaults`
/// keeps things simple for single-device use, and we layer sync in later
/// without changing the consumer surface here.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    /// The currently-selected primary theme. Setting this via `select(_:)`
    /// persists the selection and triggers view updates.
    private(set) var primary: PrimarySwatch

    private let userDefaults: UserDefaults
    private let repository: PrimaryPaletteRepository
    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "ThemeStore")

    private static let storageKey = "com.jonsung.DailyCadence.primarySwatchId"

    init(
        userDefaults: UserDefaults = .standard,
        repository: PrimaryPaletteRepository = .shared
    ) {
        self.userDefaults = userDefaults
        self.repository = repository

        let storedId = userDefaults.string(forKey: Self.storageKey)
        if let storedId, let resolved = repository.swatch(id: storedId) {
            self.primary = resolved
            log.info("Restored primary theme: \(storedId)")
        } else {
            self.primary = repository.defaultSwatch()
            if storedId != nil {
                log.info("Stored primary id '\(storedId ?? "nil")' no longer in palette; falling back to default")
            }
        }
    }

    /// Select a new primary swatch. Persists to `UserDefaults` and notifies
    /// observers on the main actor.
    func select(_ swatch: PrimarySwatch) {
        guard swatch.id != primary.id else { return }
        primary = swatch
        userDefaults.set(swatch.id, forKey: Self.storageKey)
        log.info("Primary theme changed to: \(swatch.id)")
    }

    /// Select a swatch by id. Returns `false` if no swatch with that id
    /// exists (caller may surface an error to the user).
    @discardableResult
    func select(id: String) -> Bool {
        guard let swatch = repository.swatch(id: id) else { return false }
        select(swatch)
        return true
    }

    /// Reset to the default swatch (sage). Used by Settings' "Reset to
    /// default" action in Phase B.
    func resetToDefault() {
        select(repository.defaultSwatch())
    }
}
