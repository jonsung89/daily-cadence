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
}
