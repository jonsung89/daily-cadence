import Foundation
import Observation
import OSLog

/// In-memory store for the user's notes.
///
/// Phase C scope: lives only in memory and seeds with `MockNotes.today` on
/// first launch. Notes added via the editor stick around for the session
/// but reset on relaunch — that's intentional until we wire Supabase
/// persistence in Phase 1's later rounds.
///
/// Singleton pattern matches `ThemeStore` so views can read
/// `TimelineStore.shared.notes` and the Observation framework picks up the
/// dependency automatically.
@Observable
final class TimelineStore {
    static let shared = TimelineStore()

    /// Notes for "today," in chronological order.
    private(set) var notes: [MockNote]

    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "TimelineStore")

    init(initialNotes: [MockNote] = MockNotes.today) {
        self.notes = initialNotes
    }

    /// Append a note. Phase C doesn't sort — new notes land at the end (the
    /// editor stamps them with the current wall-clock time, and most use
    /// is "log something just happened" so end-of-day ordering is correct).
    /// When backdating lands we'll insert in time-order.
    func add(_ note: MockNote) {
        notes.append(note)
        log.info("Added note: type=\(note.type.rawValue) title=\(note.timelineTitle)")
    }

    /// Removes the note with the given id. No-op if the id isn't present.
    /// Also clears the note's pin state (so deleting a pinned note doesn't
    /// leave a ghost id in `PinStore`).
    ///
    /// Phase E.5.15 — invoked from the per-card `.contextMenu` Delete
    /// action after the user confirms via `.confirmationDialog`.
    func delete(noteId: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let removed = notes.remove(at: index)
        PinStore.shared.forget(noteId)
        log.info("Deleted note: type=\(removed.type.rawValue) title=\(removed.timelineTitle)")
    }
}
