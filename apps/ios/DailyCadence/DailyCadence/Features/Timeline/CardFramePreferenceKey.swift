import SwiftUI

/// Publishes each Cards-Board card's frame (in a named coordinate
/// space) up to the grid container so the custom drag gesture can
/// hit-test the user's finger against card positions.
///
/// **Why a preference key.** SwiftUI doesn't expose subview frames to
/// a parent layout, but `PreferenceKey` lets each child publish a
/// fragment of state and the parent collect them via
/// `.onPreferenceChange(_:perform:)`. Each `KeepCard` adds a
/// transparent `GeometryReader` background that emits its single-entry
/// frame map; the grid merges them via `reduce(value:nextValue:)` and
/// stores the combined map in `DragSessionStore.cardFrames`.
///
/// The frame map is keyed by `MockNote.id` (UUID) so the gesture's
/// hit-test can look up the targeted card directly from
/// `DragSessionStore.cardFrames[hitId]` without traversing the layout.
///
/// Frames are reported in the gesture's named coordinate space
/// (`TimelineScreen.cardsGridCoordinateSpace`), which matches the
/// `DragGesture(coordinateSpace:)` used by the gesture chain. Locations
/// from drag updates and frames from the preference key are therefore
/// directly comparable.
struct CardFramePreferenceKey: PreferenceKey {
    typealias Value = [UUID: CGRect]

    static var defaultValue: Value { [:] }

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
