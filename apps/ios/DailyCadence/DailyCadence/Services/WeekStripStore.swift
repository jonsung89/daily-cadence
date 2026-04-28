import Foundation
import Observation
import OSLog

/// Phase F.1.2.weekstrip — backs the Today screen's week-strip
/// indicator. Holds the set of local-calendar days within the
/// currently-shown week that have at least one non-deleted note for
/// the signed-in user.
///
/// **Lifecycle**
/// - Loads via `load(userId:day:)` whenever `TimelineStore.selectedDate`
///   transitions to a different week. Same-week navigations don't
///   refetch (the set is already accurate).
/// - Optimistic updates on the same-week path: `noteAdded(_:)` /
///   `noteRemoved(_:occurredAt:remainingForDay:)` keep the in-memory
///   set in sync with `TimelineStore` mutations without a refetch.
///   `TimelineStore` calls these from its `add` / `update` / `delete`
///   surfaces.
///
/// **Why a separate store** rather than deriving from `TimelineStore`:
/// `TimelineStore` only carries notes for the *currently-selected*
/// day. The week strip needs visibility into the OTHER six days — a
/// dedicated bulk fetch is the right shape, and a singleton keeps
/// the cache lifecycle clean.
@Observable
@MainActor
final class WeekStripStore {
    static let shared = WeekStripStore()

    /// Days (normalized to `startOfDay`) within the currently-loaded
    /// week that have at least one note. Read by `WeekStripView` to
    /// decide which dots to fill.
    private(set) var daysWithNotes: Set<Date> = []

    /// `startOfDay` of the loaded week's first day (locale-aware
    /// `firstWeekday`). Used to detect "we're already on this week,
    /// skip the refetch."
    private(set) var weekStart: Date?

    private(set) var isLoading: Bool = false

    private let repository: NotesRepository
    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "WeekStripStore")

    init(repository: NotesRepository = .shared) {
        self.repository = repository
    }

    /// Fetches the days-with-notes set for the week containing `day`.
    /// Idempotent — same-week calls short-circuit. Cancellation-safe;
    /// failures keep the prior set rather than wiping to empty.
    func load(userId: UUID, day: Date) async {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: day) else { return }
        let normalizedStart = cal.startOfDay(for: interval.start)
        if normalizedStart == weekStart { return }
        isLoading = true
        do {
            let days = try await repository.fetchDaysWithNotes(
                userId: userId,
                weekContaining: day
            )
            weekStart = normalizedStart
            daysWithNotes = days
            log.info("Loaded \(days.count) filled days for week starting \(normalizedStart)")
        } catch is CancellationError {
            log.debug("WeekStripStore.load cancelled")
        } catch {
            log.error("WeekStripStore.load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }

    /// Optimistic add — called from `TimelineStore.add(_:)` so the
    /// strip's dot fills immediately without waiting for a refetch.
    /// No-op if the note's day falls outside the currently-loaded
    /// week (the next week-change will refetch).
    func noteAdded(occurredAt: Date?) {
        guard let occurredAt, let weekStart else { return }
        let day = Calendar.current.startOfDay(for: occurredAt)
        guard isInLoadedWeek(day) else { _ = weekStart; return }
        daysWithNotes.insert(day)
    }

    /// Optimistic remove — called from `TimelineStore.delete(_:)` with
    /// the day's remaining note count *after* the local removal. Drops
    /// the day from the set when the count hits zero. No-op if the
    /// day is outside the current week.
    func noteRemoved(occurredAt: Date?, remainingForDay: Int) {
        guard let occurredAt, weekStart != nil else { return }
        let day = Calendar.current.startOfDay(for: occurredAt)
        guard isInLoadedWeek(day) else { return }
        if remainingForDay == 0 {
            daysWithNotes.remove(day)
        }
    }

    /// Optimistic update — when a note's `occurredAt` changes (user
    /// edited the time), we may need to add the new day OR remove the
    /// old day depending on remaining-count for each side.
    func noteUpdated(
        oldOccurredAt: Date?,
        newOccurredAt: Date?,
        oldDayRemaining: Int
    ) {
        // The "add" side is unconditional — adding a note to a day
        // always fills that day's dot (or is already filled).
        noteAdded(occurredAt: newOccurredAt)
        // The "remove" side only fires when the old day's note count
        // goes to zero (i.e., the moved note was the only one there).
        noteRemoved(occurredAt: oldOccurredAt, remainingForDay: oldDayRemaining)
    }

    /// True if `day` (already normalized to startOfDay) falls within
    /// the currently-loaded week.
    private func isInLoadedWeek(_ day: Date) -> Bool {
        guard let weekStart else { return false }
        let cal = Calendar.current
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else {
            return false
        }
        return day >= weekStart && day < weekEnd
    }
}
