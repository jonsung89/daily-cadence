import Foundation
import Observation
import OSLog

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

    /// `true` once a load has completed for the **current** `selectedDate`.
    /// Reset to `false` on every `selectDate(_:)` so the skeleton shows
    /// briefly on day-switches (matches the cold-launch loading UX).
    private(set) var hasLoaded = false

    /// Last failure surface for `load` / `add` / `delete`. UI can read this
    /// to render a toast or banner; cleared on the next successful op.
    private(set) var lastError: String?

    private let repository: NotesRepository
    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "TimelineStore")

    init(initialNotes: [MockNote]? = nil, repository: NotesRepository = .shared) {
        // Production launches start empty so a fresh anon user doesn't see
        // mock-seed flash. Previews seed `MockNotes.today` so the canvas
        // renders content for layout work.
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        self.notes = initialNotes ?? (isPreview ? MockNotes.today : [])
        self.repository = repository
    }

    // MARK: - Day navigation

    /// Switches the timeline to a different local-calendar day and triggers
    /// a re-fetch. No-op if the new date normalizes to the already-selected
    /// day. Clearing `notes` immediately on switch (rather than waiting for
    /// the fetch to return) lets the skeleton show right away — feels more
    /// responsive than seeing the previous day's notes for ~200ms.
    func selectDate(_ date: Date) {
        let normalized = Calendar.current.startOfDay(for: date)
        guard normalized != selectedDate else { return }
        log.info("selectDate: \(self.selectedDate) → \(normalized)")
        selectedDate = normalized
        notes = []
        hasLoaded = false
        lastError = nil
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
    var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    // MARK: - Live load

    /// Fetches the signed-in user's notes from Supabase and replaces the
    /// in-memory list. Idempotent — safe to call repeatedly (e.g., on
    /// pull-to-refresh later).
    func load(userId: UUID) async {
        do {
            let fetched = try await repository.fetchForDay(userId: userId, day: selectedDate)
            notes = fetched
            hasLoaded = true
            lastError = nil
            log.info("Loaded \(fetched.count) notes for user \(userId)")
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

    /// Appends a note locally and persists in the background.
    func add(_ note: MockNote) {
        notes.append(note)
        log.info("Added note locally: type=\(note.type.rawValue) title=\(note.timelineTitle)")
        Task { await self.persistAdd(note) }
    }

    /// Removes the note locally (and forgets its pin state) and soft-deletes
    /// on the server in the background. No-op if the id isn't present.
    /// Phase E.5.15 — invoked from the per-card `.contextMenu` Delete action
    /// after the user confirms via `.confirmationDialog`.
    func delete(noteId: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let removed = notes.remove(at: index)
        PinStore.shared.forget(noteId)
        log.info("Deleted note locally: type=\(removed.type.rawValue) title=\(removed.timelineTitle)")
        Task { await self.persistDelete(noteId) }
    }

    // MARK: - Persistence helpers

    private func persistAdd(_ note: MockNote) async {
        guard let userId = AuthStore.shared.currentUserId else {
            log.warning("Skipping persist for added note: auth not ready (note stays in-memory only)")
            return
        }
        do {
            let serverId = try await repository.insert(note, userId: userId)
            if let serverId, let idx = notes.firstIndex(where: { $0.id == note.id }) {
                // Swap optimistic UUID for the server-canonical one so
                // subsequent edits/deletes target the right row.
                notes[idx] = MockNote(
                    id: serverId,
                    occurredAt: note.occurredAt,
                    type: note.type,
                    content: note.content,
                    background: note.background,
                    titleStyle: note.titleStyle
                )
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
