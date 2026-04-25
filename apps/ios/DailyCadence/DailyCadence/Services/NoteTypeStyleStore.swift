import Foundation
import Observation
import OSLog

/// Holds the user's per-note-type color overrides and persists them across
/// launches.
///
/// Default behavior (no overrides): each `NoteType` returns its design-system
/// pigment (workout = clay, meal = turmeric, etc. — see `NoteType.defaultColor`).
///
/// Override behavior: when the user picks a swatch in
/// `NoteTypePickerScreen`, this store maps the type's `rawValue` to the
/// swatch's id. `NoteType.color` reads through here, so the change
/// propagates everywhere a workout color is shown — type badges, timeline
/// dots, KeepCard borders, TypeChip icons.
///
/// Persistence: `UserDefaults` under a single dictionary key. Stale ids
/// (after a palette JSON update removes a swatch) gracefully fall back to
/// the type's default — same recovery pattern as `ThemeStore`.
@Observable
final class NoteTypeStyleStore {
    static let shared = NoteTypeStyleStore()

    /// Map from `NoteType.rawValue` to swatch id (e.g. `"workout" → "bold.cobalt"`).
    /// Empty dictionary means every type uses its default color.
    private(set) var overrides: [String: String]

    private let userDefaults: UserDefaults
    private let repository: PaletteRepository
    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "NoteTypeStyleStore")

    private static let storageKey = "com.jonsung.DailyCadence.noteTypeColors"

    init(
        userDefaults: UserDefaults = .standard,
        repository: PaletteRepository = .shared
    ) {
        self.userDefaults = userDefaults
        self.repository = repository
        if let stored = userDefaults.dictionary(forKey: Self.storageKey) as? [String: String] {
            self.overrides = stored
        } else {
            self.overrides = [:]
        }
    }

    // MARK: - Reads

    /// The user's chosen swatch for a type, or `nil` if there's no override
    /// (or the stored swatch id has been removed from the palette since).
    func swatch(for type: NoteType) -> Swatch? {
        guard let id = overrides[type.rawValue] else { return nil }
        return repository.swatch(id: id)
    }

    /// `true` when the user has set a custom color for this type.
    func hasOverride(for type: NoteType) -> Bool {
        overrides[type.rawValue] != nil
    }

    // MARK: - Writes

    /// Set an override for the given type. Pass `nil` to clear back to the
    /// default. Persists immediately and notifies observers.
    func setSwatchId(_ id: String?, for type: NoteType) {
        if let id, !id.isEmpty {
            overrides[type.rawValue] = id
        } else {
            overrides.removeValue(forKey: type.rawValue)
        }
        userDefaults.set(overrides, forKey: Self.storageKey)
        log.info("NoteType override updated: \(type.rawValue) → \(id ?? "default")")
    }

    /// Clear all overrides — every type returns to its design-system default.
    /// Used by Settings' "Reset to defaults" action.
    func resetAll() {
        overrides.removeAll()
        userDefaults.removeObject(forKey: Self.storageKey)
        log.info("All NoteType overrides cleared")
    }
}
