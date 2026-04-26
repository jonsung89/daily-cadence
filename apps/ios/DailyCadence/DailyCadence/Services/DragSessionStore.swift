import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Drag-to-reorder session state for the Cards Board layout.
///
/// **Phase E.5.7 — custom-gesture rewrite.** Replaces the prior
/// `.onDrag` / `.onDrop` plumbing (and the `NoteReorderDropDelegate`)
/// with a single `LongPressGesture.sequenced(before: DragGesture)` chain
/// owned by `TimelineScreen.cardsBoardGrid`. The gesture publishes
/// finger position into this store; the store hit-tests against
/// `cardFrames` (populated via a `PreferenceKey`) and drives reorder.
///
/// **Why we own hit-testing.** SwiftUI's drop-delegate system gave us
/// three structural problems (see `docs/TODO_CUSTOM_DRAG_REORDER.md`):
/// no callback when the drop landed outside any registered target, a
/// `dropEntered` cascade as cards reflowed under a stationary finger,
/// and no cancel-on-empty semantics. Owning the gesture cleanly fixes
/// all three.
///
/// **Lifecycle.**
/// - **Drag begins** (long press completes + first drag delta) →
///   `beginSession(...)` snapshots the pre-drag custom order, fires a
///   medium haptic, and publishes `activeSession`.
/// - **Drag updates** → `updateLocation(_:in:)` updates the finger's
///   current position and, if it's over a different card than the
///   `lastTargetId`, calls `CardsViewOrderStore.shared.move(...)` so
///   the surrounding cards reflow live.
/// - **Drag ends over a card** → `endDrag(finalLocation:in:)` keeps
///   the order produced by the last live move and clears the session.
/// - **Drag ends over empty space** → `endDrag(...)` calls
///   `CardsViewOrderStore.shared.restore(_:)` with the snapshot, so
///   the order returns to where it was at drag start.
///
/// **`draggingNoteId` / `currentDropTargetId`** are kept as computed
/// projections off `activeSession` so the existing source-fade and
/// drop-target outline view code (Phase E.5.5) keeps working unchanged.
@Observable
final class DragSessionStore {
    static let shared = DragSessionStore()

    /// The active drag session, or `nil` if no card is being dragged.
    /// Set in `beginSession`, cleared in `endDrag`.
    var activeSession: DragSession?

    /// The card whose long press has completed but whose drag hasn't
    /// started moving yet — i.e. "lifted, awaiting drag." Cards read
    /// this to render a slight scale + shadow so the user has visual
    /// confirmation that they held long enough to enter drag mode,
    /// independent of any actual finger movement.
    ///
    /// Cleared at the moment the drag starts moving (handed off to
    /// `activeSession`'s fade + floating preview) and on every
    /// `onEnded` so a no-movement release lands back at rest.
    var liftedNoteId: UUID?

    /// The cards-grid-space location of the finger at the moment the
    /// long-press succeeded. Captured in `liftSource` and consumed by
    /// `beginSession` on the first drag movement so the floating
    /// preview's grab offset is computed against where the finger
    /// actually landed — not where it's already moved to by the first
    /// `.changed` callback. Cleared in `beginSession` and `cancelSession`.
    var liftLocation: CGPoint?

    /// Map of card id → its frame in the cards-grid coordinate space.
    /// Published by each card via a `PreferenceKey` and read here for
    /// hit-testing during a drag.
    var cardFrames: [UUID: CGRect] = [:]

    /// Convenience read for the source-fade visual (Phase E.5.5).
    /// Reading this inside a `body` registers the view as an observer,
    /// so the source card re-renders when the drag begins / ends.
    var draggingNoteId: UUID? { activeSession?.noteId }

    /// Convenience read for the live drop-target outline (Phase E.5.5).
    /// Mirrors `activeSession.lastTargetId` — the card the finger most
    /// recently moved over (which is also where the dragged card was
    /// reordered to). Cleared at end-of-drag.
    var currentDropTargetId: UUID? { activeSession?.lastTargetId }

    init() {}

    /// Marks `noteId` as "lifted" — the long press has completed but
    /// the user hasn't started moving yet. Captures `location` (in the
    /// cards-grid coordinate space) so `beginSession` can compute a
    /// stable grab offset on the first drag movement. Idempotent across
    /// repeat calls for the same id.
    ///
    /// Fires a medium-impact haptic to confirm "you held long enough."
    func liftSource(noteId: UUID, at location: CGPoint) {
        guard liftedNoteId != noteId else { return }
        liftedNoteId = noteId
        liftLocation = location
        Self.fireHaptic(.medium)
    }

    /// Starts a drag session. Captures the pre-drag custom order so an
    /// "end on empty space" can revert to it. Hands off from the lifted
    /// state — the lifted scale + shadow goes away as the floating
    /// preview takes over.
    func beginSession(
        noteId: UUID,
        location: CGPoint,
        grabOffset: CGSize,
        preDragOrder: [UUID]
    ) {
        activeSession = DragSession(
            noteId: noteId,
            currentLocation: location,
            grabOffset: grabOffset,
            preDragOrder: preDragOrder,
            lastTargetId: nil
        )
        liftedNoteId = nil
        liftLocation = nil
    }

    /// Updates the finger location during a drag. If the finger is now
    /// over a card that isn't the source and isn't the most-recent
    /// target, runs the live reorder. Cards under the finger animate
    /// into their new positions inside an `.easeOut(0.18)` block.
    func updateLocation(_ location: CGPoint, in notes: [MockNote]) {
        guard var session = activeSession else { return }
        session.currentLocation = location

        if let target = noteAt(location, in: notes),
           target.id != session.noteId,
           target.id != session.lastTargetId {
            session.lastTargetId = target.id
            withAnimation(.easeOut(duration: 0.18)) {
                CardsViewOrderStore.shared.move(
                    session.noteId,
                    before: target.id,
                    in: notes
                )
            }
        }

        activeSession = session
    }

    /// Ends a drag session. If `finalLocation` is over a card, the
    /// current (already-reordered) layout is committed. Otherwise the
    /// pre-drag order is restored. Either way, the session clears so
    /// the source card un-fades and the drop-target outline goes away.
    func endDrag(finalLocation: CGPoint?, in notes: [MockNote]) {
        // Always clear the lifted state at end-of-gesture, including the
        // long-press-then-release-without-moving case where there's no
        // active session to clear.
        liftedNoteId = nil
        liftLocation = nil

        guard let session = activeSession else { return }

        let droppedOnCard: Bool = {
            guard let location = finalLocation else { return false }
            return noteAt(location, in: notes) != nil
        }()

        if droppedOnCard {
            Self.fireHaptic(.light)
        } else {
            withAnimation(.easeOut(duration: 0.22)) {
                CardsViewOrderStore.shared.restore(session.preDragOrder)
            }
        }

        activeSession = nil
    }

    /// Cancel any in-flight session without committing or reverting.
    /// Used as a safety net if the gesture system delivers an `onEnded`
    /// callback we can't classify. Also clears the lifted-but-not-
    /// dragging state so a long-press-and-release doesn't leave the
    /// source card scaled up.
    func cancelSession() {
        activeSession = nil
        liftedNoteId = nil
        liftLocation = nil
    }

    // MARK: - Hit-testing

    private func noteAt(_ location: CGPoint, in notes: [MockNote]) -> MockNote? {
        for note in notes {
            if let frame = cardFrames[note.id], frame.contains(location) {
                return note
            }
        }
        return nil
    }

    // MARK: - Haptics

    private static func fireHaptic(_ style: HapticStyle) {
        #if canImport(UIKit)
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .medium: generator = UIImpactFeedbackGenerator(style: .medium)
        case .light:  generator = UIImpactFeedbackGenerator(style: .light)
        }
        generator.impactOccurred()
        #endif
    }

    private enum HapticStyle { case light, medium }
}

/// Snapshot of an in-progress drag. Held by `DragSessionStore`.
///
/// `grabOffset` is the vector from the source card's center to the
/// finger at drag start — applied when rendering the floating preview
/// so the card stays "in hand" instead of jumping to be centered on
/// the finger when the drag begins.
struct DragSession: Equatable {
    let noteId: UUID
    var currentLocation: CGPoint
    let grabOffset: CGSize
    let preDragOrder: [UUID]
    var lastTargetId: UUID?
}
