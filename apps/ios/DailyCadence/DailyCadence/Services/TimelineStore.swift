import Foundation
import Observation
import OSLog
import SwiftUI
import UIKit

/// In-memory store for the user's notes.
///
/// Phase F.0.2 wires this to `NotesRepository`. On launch, after `AuthStore`
/// finishes its bootstrap, `load(userId:)` fetches the user's persisted
/// notes from Supabase and populates the list.
///
/// **Mutations stay synchronous to callers.** `add(_:)` and `delete(noteId:)`
/// update the in-memory list immediately and spawn an internal `Task` to
/// persist in the background — the editor's Save button dismisses the
/// sheet without waiting on the network. On insert success the optimistic
/// row's UUID gets swapped for the server-canonical one so subsequent
/// edits/deletes target the right row. On insert failure the optimistic
/// row is reverted and `lastError` is set; on delete failure we don't
/// revert (user already saw the note disappear) but `lastError` surfaces
/// for diagnostics.
///
/// **Seed behavior:** at runtime, `notes` starts empty and is populated by
/// `load(userId:)`. Showing fake mock notes for the brief window before
/// `load` returns would flash other people's content into a fresh user's
/// timeline. SwiftUI Previews are detected via the
/// `XCODE_RUNNING_FOR_PREVIEWS` environment variable and seed
/// `MockNotes.today` so the preview canvas keeps rendering content for
/// layout iteration. (Component-level previews — `NoteCard`, `KeepGrid`,
/// `TimelineItem` — pass mock data in directly and are unaffected.)
///
/// Singleton pattern matches `ThemeStore` so views can read
/// `TimelineStore.shared.notes` and the Observation framework picks up the
/// dependency automatically.
@Observable
final class TimelineStore {
    static let shared = TimelineStore()

    /// Notes for the currently-`selectedDate`, in chronological order.
    private(set) var notes: [MockNote]

    /// The local-calendar day the timeline is currently showing. Defaults
    /// to today; changed via `selectDate(_:)` / `goToPreviousDay()` / etc.
    /// Always normalized to `Calendar.current.startOfDay(for:)` so reads
    /// in views compare cleanly across re-renders.
    private(set) var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    /// Phase F.1.2.midnight — observable source of truth for "what is
    /// today's local-calendar day." Views that ask "is X today?" read
    /// this and compare instead of calling `Calendar.current.isDateInToday(_:)`
    /// directly — the latter reads `Date()` each invocation but isn't
    /// observed, so views go stale at midnight. This is observed via
    /// the `@Observable` macro on the class, so reading it inside a
    /// view's `body` registers the dependency and triggers a re-render
    /// when `refreshCurrentDay()` advances it.
    ///
    /// **Update sources** (subscribed in `init`):
    /// - `UIApplication.significantTimeChangeNotification` — iOS posts
    ///   this at midnight, on time-zone change, on DST shift, and on
    ///   manual clock changes. Same notification Apple's own date-aware
    ///   apps (Calendar, Reminders, Stocks) consume. Fires while the app
    ///   is foreground; queued and delivered at next foreground
    ///   transition when the app is suspended.
    /// - `RootView` calls `refreshCurrentDay()` on `scenePhase == .active`
    ///   to belt-and-suspender the suspended-across-midnight case.
    ///
    /// `selectedDate` is **not** auto-advanced when this changes. The
    /// user explicitly chose what day to view; midnight shouldn't yank
    /// them. The Today pill becomes their way back.
    private(set) var currentDay: Date = Calendar.current.startOfDay(for: .now)

    /// `true` once a load has completed for the **current** `selectedDate`.
    /// Reset to `false` on every `selectDate(_:)` so the skeleton shows
    /// briefly on day-switches (matches the cold-launch loading UX).
    private(set) var hasLoaded = false

    /// Last failure surface for `load` / `add` / `delete`. UI can read this
    /// to render a toast or banner; cleared on the next successful op.
    private(set) var lastError: String?

    /// Phase F.1.2.daycache — in-memory cache of previously-loaded days
    /// keyed by `startOfDay`. Hydrating from this on `selectDate` skips
    /// the empty-flash that used to appear when navigating between days
    /// (clear → fetch → render). Pattern: stale-while-cached. Mutations
    /// (`add` / `update` / `delete`) mirror into this map so it stays
    /// consistent with the live `notes` array. Cleared via
    /// `clearDayCache()` when a new user signs in (called from
    /// `AuthStore` — when real auth ships; today's anon-only flow never
    /// hits user-change).
    ///
    /// **Not observed.** Plain dict, not `@Observable`-projected — the
    /// observable surface stays `notes` (the currently-shown day). The
    /// cache is internal plumbing.
    ///
    /// **No TTL** for Phase 1: in-session navigations always read from
    /// cache when present, so a user looking at yesterday won't see
    /// changes made by another device until they sign out + back in.
    /// Acceptable until pull-to-refresh / realtime sync ship — both
    /// will provide explicit invalidation hooks.
    private var notesByDay: [Date: [MockNote]] = [:]

    private let repository: NotesRepository
    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "TimelineStore")

    init(initialNotes: [MockNote]? = nil, repository: NotesRepository = .shared) {
        // Production launches start empty so a fresh anon user doesn't see
        // mock-seed flash. Previews seed `MockNotes.today` so the canvas
        // renders content for layout work.
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        self.notes = initialNotes ?? (isPreview ? MockNotes.today : [])
        self.repository = repository

        // Phase F.1.2.midnight — system-driven day rollover. Singleton
        // lives forever, so we never need to remove this observer (no
        // deinit ever runs). Closure-based `addObserver` keeps the
        // handler off the SwiftUI view layer where it belongs.
        NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshCurrentDay()
        }
    }

    /// Idempotent — compares the stored `currentDay` to the system's
    /// real-now day; no-ops when they match, animates the rollover when
    /// they don't. Safe to call from any code path that suspects the
    /// day might have shifted: the system midnight notification, app
    /// foreground transitions, manual time-zone changes. Wrapping the
    /// write in `withAnimation` lets every observer (date header, Today
    /// pill, week strip) crossfade / slide rather than snap.
    func refreshCurrentDay() {
        let actualDay = Calendar.current.startOfDay(for: .now)
        guard actualDay != currentDay else { return }
        log.info("currentDay rollover: \(self.currentDay) → \(actualDay)")
        withAnimation(.smooth(duration: 0.5)) {
            currentDay = actualDay
        }
    }

    // MARK: - Day navigation

    /// Switches the timeline to a different local-calendar day. Phase
    /// F.1.2.daycache — if we've already loaded this day in this
    /// session, hydrate from `notesByDay` immediately so the empty
    /// state doesn't flash. **`hasLoaded` stays false** so the
    /// background refetch still fires (the cache is an initial-render
    /// hint, not a fetch-skip); the resulting `load()` does a surgical
    /// merge against the hydrated notes so unchanged items don't churn.
    /// Cache miss falls back to the original behavior (empty + fetch +
    /// empty state shown until fetch returns).
    func selectDate(_ date: Date) {
        let normalized = Calendar.current.startOfDay(for: date)
        guard normalized != selectedDate else { return }
        log.info("selectDate: \(self.selectedDate) → \(normalized)")
        selectedDate = normalized
        if let cached = notesByDay[normalized] {
            notes = cached
        } else {
            notes = []
        }
        hasLoaded = false
        lastError = nil
    }

    /// Phase F.1.2.daycache — drops every cached day. Intended for
    /// auth changes (real Sign in with Apple ships in a future round
    /// and will need this hook so user A's cached days don't bleed into
    /// user B's session). No-op-safe today since the anon-only flow
    /// never changes user.
    func clearDayCache() {
        notesByDay.removeAll()
        log.info("Cleared day cache")
    }

    /// Convenience: jumps to today. Used by the "Today" pill that appears
    /// when viewing a non-today date.
    func goToToday() {
        selectDate(.now)
    }

    /// Convenience: shifts `selectedDate` by `days` (negative = past).
    /// Header chevrons + swipe gestures call this with `-1` / `+1`.
    func shiftSelectedDate(byDays days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDate)
        else { return }
        selectDate(next)
    }

    /// `true` when `selectedDate` is today's local-calendar day. Drives the
    /// "Today" pill's visibility.
    ///
    /// Phase F.1.2.midnight — compares against the observed `currentDay`
    /// instead of `Calendar.current.isDateInToday(selectedDate)`. The
    /// latter reads `Date()` each call but isn't observed, so the pill's
    /// visibility wouldn't update at midnight. With this comparison,
    /// every observer of `currentDay` re-evaluates `isViewingToday`
    /// when midnight rolls over.
    var isViewingToday: Bool {
        selectedDate == currentDay
    }

    // MARK: - Live load

    /// Fetches the signed-in user's notes from Supabase and replaces the
    /// in-memory list. Idempotent — safe to call repeatedly (e.g., on
    /// pull-to-refresh later).
    func load(userId: UUID) async {
        do {
            let day = selectedDate
            let fetched = try await repository.fetchForDay(userId: userId, day: day)
            // Race guard: the user could have switched days while the
            // fetch was in flight. Apply only when the request matches
            // the still-selected day; the cache update is keyed by `day`
            // either way so a stale fetch still warms the cache for the
            // day it was about (no harm, no UI thrash).
            notesByDay[day] = fetched
            if day == selectedDate {
                // Phase F.1.2.daycache — surgical merge against the
                // currently-rendered notes (which may have come from
                // the cache hydration in selectDate). Updates affected
                // notes in place, removes ones that no longer exist on
                // the server, inserts new ones. Avoids a full-array
                // replace so SwiftUI's diffing has minimal work and
                // the UI doesn't churn when the fetch returns a
                // mostly-unchanged set.
                mergeFetched(fetched)
                hasLoaded = true
                lastError = nil
            }
            log.info("Loaded \(fetched.count) notes for user \(userId) day=\(day)")
        } catch is CancellationError {
            // SwiftUI's `.task(id:)` cancels the prior task when the id
            // transitions (e.g., AuthStore's currentUserId settles
            // nil → uuid). The next cycle retries successfully. Don't
            // surface as an error; don't set `lastError`.
            log.debug("load cancelled (auth state re-emit; will retry on next .task cycle)")
        } catch {
            // Keep the existing in-memory notes on failure rather than
            // wiping to an empty list — better cold-start UX when the
            // user opens the app offline.
            lastError = error.localizedDescription
            log.error("load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Mutations (sync surface, async persist)

    /// Inserts a note locally — sorted into chronological position by
    /// `occurredAt` ascending — and persists in the background. The sort
    /// matches the server's `order("occurred_at", ascending: true)` so
    /// the next refresh produces the same layout. Without the in-memory
    /// sort, a past-event note (user picks an earlier time) lands at
    /// the bottom until refresh.
    func add(_ note: MockNote) {
        notes.append(note)
        sortByOccurredAtAscending()
        notesByDay[selectedDate] = notes  // Phase F.1.2.daycache — keep cache in lock-step
        // Cross-day add (rare — editor defaults to selectedDate, but the
        // user can change the picker): invalidate the destination day's
        // cache so when they navigate there it refetches and includes
        // this note. Without this, stale cache would hide the new note.
        let noteDay = note.occurredAt.map { Calendar.current.startOfDay(for: $0) }
        if let noteDay, noteDay != selectedDate {
            notesByDay.removeValue(forKey: noteDay)
        }
        log.info("Added note locally: type=\(note.type.rawValue) title=\(note.timelineTitle)")
        // Phase F.1.2.weekstrip — keep the week-strip indicator in
        // sync with the in-memory mutation. Same-week adds fill the
        // dot immediately; cross-week adds are no-ops here and pick
        // up via the next week-change refetch.
        WeekStripStore.shared.noteAdded(occurredAt: note.occurredAt)
        Task { await self.persistAdd(note) }
    }

    /// Replaces the note with the given id with `updated`. Optimistic —
    /// the in-memory swap happens immediately; the repository call runs
    /// in the background. On failure, reverts to the previous version
    /// and surfaces `lastError`. No-op if the id isn't present.
    ///
    /// Re-sorts after the swap because the user may have changed
    /// `occurredAt` during edit, which would land the note in a new
    /// chronological position.
    ///
    /// Phase F.1.0 — invoked from `NoteEditorScreen` Save when the screen
    /// was opened in edit mode (`editing: MockNote?` non-nil).
    func update(_ updated: MockNote) {
        guard let index = notes.firstIndex(where: { $0.id == updated.id }) else { return }
        let previous = notes[index]
        notes[index] = updated
        sortByOccurredAtAscending()
        notesByDay[selectedDate] = notes  // Phase F.1.2.daycache — keep cache in lock-step
        // Cross-day update (user changed `occurredAt` to a different
        // day): invalidate the destination day's cache so the moved
        // note will appear when the user navigates there.
        let oldDay = previous.occurredAt.map { Calendar.current.startOfDay(for: $0) }
        let newDay = updated.occurredAt.map { Calendar.current.startOfDay(for: $0) }
        if oldDay != newDay, let newDay {
            notesByDay.removeValue(forKey: newDay)
        }
        log.info("Updated note locally: id=\(updated.id) type=\(updated.type.rawValue)")
        // Phase F.1.2.weekstrip — if the user changed `occurredAt`
        // during edit, the strip's dot positions may need to shift.
        // Compute the OLD day's remaining count (excluding this note,
        // since we already swapped it) so the store knows whether to
        // empty that day's dot. (`oldDay` declared above for the
        // cache-invalidation path; reused here.)
        let oldDayRemaining = oldDay.map { day in
            notes.filter {
                $0.id != updated.id &&
                $0.occurredAt.map(Calendar.current.startOfDay(for:)) == day
            }.count
        } ?? 0
        WeekStripStore.shared.noteUpdated(
            oldOccurredAt: previous.occurredAt,
            newOccurredAt: updated.occurredAt,
            oldDayRemaining: oldDayRemaining
        )
        Task { await self.persistUpdate(updated, fallback: previous) }
    }

    /// Sorts `notes` by `occurredAt` ascending. Mirrors
    /// `repository.fetchForDay`'s server-side ORDER BY so an in-memory
    /// add/update produces the same layout as the next refresh. Notes
    /// with no `occurredAt` (evergreen — currently unreachable in
    /// Phase 1, but the model permits nil) sort to the end via
    /// `.distantFuture`, matching Postgres's NULLS LAST default for ASC.
    /// Swift's `sort(by:)` is stable, so notes that share a timestamp
    /// keep their relative insertion order.
    private func sortByOccurredAtAscending() {
        notes.sort {
            ($0.occurredAt ?? .distantFuture) < ($1.occurredAt ?? .distantFuture)
        }
    }

    /// Phase F.1.2.daycache — surgical reconciliation of the server's
    /// fetched set against the currently-rendered `notes`. Replaces
    /// the historical `notes = fetched` full-array swap with a
    /// per-id diff that:
    ///
    /// - **Removes** notes whose ids no longer exist on the server
    ///   (deleted from another device, etc.)
    /// - **Updates in place** notes whose ids match — overwrites with
    ///   the server's version so any field changes propagate. SwiftUI's
    ///   ForEach keeps view identity by id, so unchanged-rendered-output
    ///   updates are graceful (no scroll jump, no insertion / removal
    ///   animations).
    /// - **Appends** notes that exist on the server but not yet locally,
    ///   then re-sorts to land them in the right chronological slot.
    ///
    /// On a cold load (notes was empty), this collapses to "append
    /// everything and sort" — same effective output as the prior
    /// `notes = fetched` for the empty-start case, just routed through
    /// the same code path.
    private func mergeFetched(_ fetched: [MockNote]) {
        let fetchedById = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })

        // Drop notes the server no longer has.
        notes.removeAll { fetchedById[$0.id] == nil }

        // Overwrite existing notes with the server's version, **only
        // when content actually differs**. The equality check matters
        // because @Observable fires for every array write, even when
        // the assigned element is value-equal to the existing one. A
        // blind `notes[i] = fresh` triggers re-render of every card
        // body — and for image-background notes that means re-decoding
        // the freshly-downloaded `Data` into a new `UIImage`, which
        // visibly flickers the background even though the image bytes
        // are identical. Equality short-circuits avoid this churn for
        // the common refetch case (no real change).
        var presentIds: Set<UUID> = []
        for i in notes.indices {
            if let fresh = fetchedById[notes[i].id] {
                if notes[i] != fresh {
                    notes[i] = fresh
                }
                presentIds.insert(fresh.id)
            }
        }

        // Insert anything new.
        for note in fetched where !presentIds.contains(note.id) {
            notes.append(note)
        }

        // Guard the sort too — only resort when the array's actual
        // ordering has shifted (insertions or per-note `occurredAt`
        // changes), so a no-op refetch doesn't trigger a write.
        if !isAlreadySortedAscending() {
            sortByOccurredAtAscending()
        }
    }

    /// Cheap pre-check for `mergeFetched` so a no-op refetch (cache
    /// already matches server) doesn't trigger an array write through
    /// `sort(by:)`. Walks once, O(n); short-circuits at the first
    /// out-of-order pair.
    private func isAlreadySortedAscending() -> Bool {
        var previous: Date = .distantPast
        for note in notes {
            let stamp = note.occurredAt ?? .distantFuture
            if stamp < previous { return false }
            previous = stamp
        }
        return true
    }

    /// Removes the note locally (and forgets its pin state) and soft-deletes
    /// on the server in the background. No-op if the id isn't present.
    /// Phase E.5.15 — invoked from the per-card `.contextMenu` Delete action
    /// after the user confirms via `.confirmationDialog`.
    func delete(noteId: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let removed = notes.remove(at: index)
        notesByDay[selectedDate] = notes  // Phase F.1.2.daycache — keep cache in lock-step
        // Defensive: if the deleted note was on a different day (rare —
        // pre-existing edge case where a note can be in `notes` despite
        // having a different `occurredAt`), invalidate that day's cache
        // too so the deletion takes effect on next navigation.
        let removedDay = removed.occurredAt.map { Calendar.current.startOfDay(for: $0) }
        if let removedDay, removedDay != selectedDate {
            notesByDay.removeValue(forKey: removedDay)
        }
        PinStore.shared.forget(noteId)
        log.info("Deleted note locally: type=\(removed.type.rawValue) title=\(removed.timelineTitle)")
        // Phase F.1.2.weekstrip — if this was the last note on its
        // day, drop the day from the filled set so the strip's dot
        // empties. Day count is computed AFTER the local removal.
        // (`removedDay` declared above for the cache-invalidation path;
        // reused here.)
        let dayRemaining = removedDay.map { day in
            notes.filter {
                $0.occurredAt.map(Calendar.current.startOfDay(for:)) == day
            }.count
        } ?? 0
        WeekStripStore.shared.noteRemoved(
            occurredAt: removed.occurredAt,
            remainingForDay: dayRemaining
        )
        Task { await self.persistDelete(noteId) }
    }

    // MARK: - Persistence helpers

    private func persistAdd(_ note: MockNote) async {
        guard let userId = AuthStore.shared.currentUserId else {
            log.warning("Skipping persist for added note: auth not ready (note stays in-memory only)")
            return
        }
        do {
            // No UUID swap — `note.id` is the client-supplied id used by
            // both client and server (NoteRowInsert.id = note.id). Same
            // UUID throughout the lifecycle eliminates a class of races
            // between this background upload+insert and concurrent user
            // actions (delete / edit while the upload is in flight).
            _ = try await repository.insert(note, userId: userId)

            // Race guard: did the user delete this note during the
            // upload? Local removal was a no-op against the server
            // because the row didn't exist yet — now that it does,
            // soft-delete it so the row doesn't resurrect on next
            // fetch. Critical for media notes where uploads take real
            // time. Fire-and-forget; if the follow-up delete fails
            // we'll catch the orphan on a future cleanup pass.
            if !notes.contains(where: { $0.id == note.id }) {
                log.info("Note \(note.id) deleted during upload — soft-deleting server-side")
                try? await repository.delete(id: note.id)
            }
            lastError = nil
        } catch {
            // Revert the optimistic insert so the timeline doesn't carry
            // a phantom row that will never persist.
            if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                notes.remove(at: idx)
            }
            lastError = error.localizedDescription
            log.error("add failed, reverted: \(error.localizedDescription)")
        }
    }

    private func persistUpdate(_ updated: MockNote, fallback previous: MockNote) async {
        guard let userId = AuthStore.shared.currentUserId else {
            log.warning("Skipping persist for updated note: auth not ready (in-memory edit only)")
            return
        }
        do {
            try await repository.update(updated, userId: userId)
            lastError = nil
        } catch {
            // Revert to the previous version so the timeline stays
            // consistent with what's actually persisted server-side.
            if let idx = notes.firstIndex(where: { $0.id == updated.id }) {
                notes[idx] = previous
            }
            lastError = error.localizedDescription
            log.error("update failed, reverted: \(error.localizedDescription)")
        }
    }

    private func persistDelete(_ noteId: UUID) async {
        do {
            try await repository.delete(id: noteId)
            lastError = nil
        } catch {
            // Local removal already happened; user sees the note gone.
            // Surface the error for diagnostics; don't try to re-insert.
            lastError = error.localizedDescription
            log.error("delete persist failed: \(error.localizedDescription)")
        }
    }
}
