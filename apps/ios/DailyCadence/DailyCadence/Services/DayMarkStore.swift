import Foundation
import Observation
import OSLog

/// Phase F.1.2.daymarks — in-memory cache of per-day emoji markers,
/// backed by `DayMarkRepository`. One entry per (user, day); the
/// week strip reads from this store via `emoji(for:)` to render the
/// top-right corner badge on each day cell.
///
/// **Lifecycle**
/// - Loads via `load(userId:)` once per session — the full set is
///   small (most users have a handful of marked days) so a single
///   bulk fetch on launch beats per-week refetches.
/// - Mutations (`set(day:emoji:)` / `clear(day:)`) update the in-memory
///   dict optimistically and persist to Supabase in the background.
///   Failures revert the optimistic change and surface `lastError`.
/// - `resetForUserChange()` wipes state when the signed-in user
///   changes — same pattern as `TimelineStore` / `WeekStripStore`.
///
/// Singleton matches the other stores so views can read
/// `DayMarkStore.shared.emoji(for: day)` and have Observation pick up
/// the dependency automatically.
@Observable
@MainActor
final class DayMarkStore {
    static let shared = DayMarkStore()

    /// `[startOfDay: emoji]` — the source of truth for week-strip
    /// emoji rendering. Keys are normalized via
    /// `Calendar.current.startOfDay(for:)` so day equality just works.
    private(set) var marks: [Date: String] = [:]

    /// `true` once the bulk fetch has completed for the current
    /// session. Reset to `false` in `resetForUserChange`.
    private(set) var hasLoaded = false

    /// Last failure message from `load` / `set` / `clear`. Cleared on
    /// the next successful op. Currently surfaced only via logs; UI
    /// could read this in a future pass for inline error toasts.
    private(set) var lastError: String?

    private let repository: DayMarkRepository
    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "DayMarkStore")

    init(repository: DayMarkRepository = .shared) {
        self.repository = repository
    }

    /// Read accessor used by the week-strip and any future surface
    /// (timeline header, calendar tab) that wants to render the
    /// emoji for a given day. `day` doesn't need to be pre-normalized
    /// — the store does that internally so views can pass a raw
    /// `Date` from `selectedDate` / strip arrays without ceremony.
    func emoji(for day: Date) -> String? {
        marks[Calendar.current.startOfDay(for: day)]
    }

    /// Wipe user-scoped state. Called from `AuthStore` when
    /// `currentUserId` changes so user A's emojis don't bleed into
    /// user B's session.
    func resetForUserChange() {
        marks = [:]
        hasLoaded = false
        lastError = nil
        log.info("Reset for user change")
    }

    /// Bulk load on launch + on user-change. Idempotent — a second
    /// call is wasted bandwidth but otherwise safe; views guard via
    /// `hasLoaded` upstream.
    func load(userId: UUID) async {
        do {
            let fetched = try await repository.fetchAll(userId: userId)
            marks = fetched
            hasLoaded = true
            lastError = nil
            log.info("Loaded \(fetched.count) day marks for user \(userId)")
        } catch is CancellationError {
            log.debug("DayMarkStore.load cancelled")
        } catch {
            lastError = error.localizedDescription
            log.error("DayMarkStore.load failed: \(error.localizedDescription)")
        }
    }

    /// Optimistic set — updates the in-memory dict immediately and
    /// upserts to Supabase in the background. On failure, reverts to
    /// the previous value (or removes the entry if there wasn't one)
    /// and sets `lastError`.
    func set(day: Date, emoji: String) {
        let key = Calendar.current.startOfDay(for: day)
        let previous = marks[key]
        marks[key] = emoji
        Task { await self.persistSet(day: key, emoji: emoji, previous: previous) }
    }

    /// Optimistic clear — removes the in-memory entry and deletes
    /// from Supabase in the background. On failure, restores the
    /// previous value (rare; a delete that fails after a successful
    /// upsert is an unlikely edge) and sets `lastError`.
    func clear(day: Date) {
        let key = Calendar.current.startOfDay(for: day)
        guard let previous = marks.removeValue(forKey: key) else { return }
        Task { await self.persistClear(day: key, previous: previous) }
    }

    private func persistSet(day: Date, emoji: String, previous: String?) async {
        guard let userId = AuthStore.shared.currentUserId else {
            log.warning("Skipping persist for day mark set: auth not ready")
            return
        }
        do {
            try await repository.setMark(userId: userId, day: day, emoji: emoji)
            lastError = nil
        } catch {
            // Revert the optimistic change.
            if let previous {
                marks[day] = previous
            } else {
                marks.removeValue(forKey: day)
            }
            lastError = error.localizedDescription
            log.error("setMark failed, reverted: \(error.localizedDescription)")
        }
    }

    private func persistClear(day: Date, previous: String) async {
        guard let userId = AuthStore.shared.currentUserId else {
            log.warning("Skipping persist for day mark clear: auth not ready")
            return
        }
        do {
            try await repository.clearMark(userId: userId, day: day)
            lastError = nil
        } catch {
            // Restore — a failed delete after a successful prior upsert
            // would otherwise leave server + client divergent.
            marks[day] = previous
            lastError = error.localizedDescription
            log.error("clearMark failed, reverted: \(error.localizedDescription)")
        }
    }
}
