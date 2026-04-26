import SwiftUI
import UIKit

/// UIKit-bridged long-press recognizer for the Cards Board layout's
/// drag-to-reorder.
///
/// **Why UIKit instead of `LongPressGesture(...).sequenced(before: DragGesture(...))`.**
/// SwiftUI's sequenced+simultaneous gesture chain — even with
/// `.simultaneousGesture` — claims the touch sequence in a way that
/// blocks the parent `ScrollView`'s pan recognizer from engaging on
/// touches that started over a card. Symptom: the page can only be
/// scrolled by panning from empty space outside the cards.
///
/// `UILongPressGestureRecognizer` participates in iOS's gesture
/// arbitration at the UIKit layer, where:
/// - `cancelsTouchesInView = false` keeps touches flowing through the
///   underlying view hierarchy without being eaten by the recognizer;
/// - a `UIGestureRecognizerDelegate` returning `true` for
///   `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` lets
///   the parent `ScrollView`'s pan and our long-press track the same
///   touch sequence in parallel.
/// Net result: scrolling works regardless of where the finger lands,
/// and the lift only fires once the finger has held still for the
/// configured duration.
///
/// **Single recognizer, no sequenced chain.** Once the press duration
/// elapses, the recognizer transitions to `.began` (the lift) and
/// reports finger movement via `.changed` (the drag) until release
/// (`.ended`). One state machine — no SwiftUI value-type discriminating
/// across `.first(true)` / `.second(true, _)` callbacks, and no
/// `@GestureState` shim to drive `.updating`.
///
/// **iOS 18+** — uses `UIGestureRecognizerRepresentable`, the modern
/// SwiftUI bridge for UIKit recognizers. The app's deployment target
/// is iOS 26 so this is unconditionally available.
struct CardReorderRecognizer: UIGestureRecognizerRepresentable {
    /// Lifecycle events surfaced to the caller. The CGPoint payload
    /// is already in the named coordinate space passed to `init` —
    /// callers don't need to do any further translation.
    enum Event {
        case began(at: CGPoint)
        case changed(to: CGPoint)
        case ended(at: CGPoint)
        case cancelled
    }

    /// Acts as the recognizer's `UIGestureRecognizerDelegate`. The
    /// only responsibility: tell UIKit that our long-press should
    /// recognize simultaneously with everything else (notably the
    /// parent `ScrollView`'s pan recognizer).
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    /// Coordinate space (e.g. `.named("cardsGridSpace")`) every event
    /// CGPoint is reported in. The recognizer asks `context.converter`
    /// for the touch location in this space directly.
    let coordinateSpace: NamedCoordinateSpace

    /// `UILongPressGestureRecognizer.minimumPressDuration` — how long
    /// the user must hold before the gesture transitions to `.began`.
    let minimumDuration: TimeInterval

    let onEvent: (Event) -> Void

    init(
        coordinateSpace: NamedCoordinateSpace,
        minimumDuration: TimeInterval = 0.4,
        onEvent: @escaping (Event) -> Void
    ) {
        self.coordinateSpace = coordinateSpace
        self.minimumDuration = minimumDuration
        self.onEvent = onEvent
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = 10
        // Don't swallow touches on the way to the parent ScrollView's
        // pan recognizer.
        recognizer.cancelsTouchesInView = false
        // Drives `shouldRecognizeSimultaneouslyWith` so the long-press
        // and the ScrollView's pan track the same touch in parallel.
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        recognizer.minimumPressDuration = minimumDuration
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        let inSpace = context.converter.location(in: coordinateSpace)
        switch recognizer.state {
        case .began:
            onEvent(.began(at: inSpace))
        case .changed:
            onEvent(.changed(to: inSpace))
        case .ended:
            onEvent(.ended(at: inSpace))
        case .cancelled, .failed:
            onEvent(.cancelled)
        default:
            break
        }
    }
}
