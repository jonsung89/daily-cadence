import SwiftUI

/// Phase F.1.1b'.zoom — bundles the tap callback + currently-presented
/// id that cards need to opt into the custom Apple Photos-style zoom.
///
/// **Why a struct, not a couple parameters.** Cards already take half a
/// dozen optional parameters; a single optional `MediaTapHandler` keeps
/// the API legible.
///
/// **Lifecycle.** `RootView` owns:
/// - `@State var presentedMedia: PresentedMedia?` — drives the overlay
/// - `@State var hidingMedia: PresentedMedia?` — keeps the overlay
///   rendered during the close animation (cleared on a delayed task)
/// - `@State var sourceFrames: [UUID: CGRect]` — collected via
///   `CardFrameKey` `PreferenceKey`, used to snapshot a source frame
///   onto `PresentedMedia` at tap time
/// - `@State var openProgress: CGFloat` — 0 at source, 1 at fullscreen
///
/// Each card forwards its tap to `onTap(payload, sourceID)` so RootView
/// can build the `PresentedMedia` snapshot and animate `openProgress`.
struct MediaTapHandler: Equatable {
    /// Drives matched-geo `isSource` — the ANIMATION trigger.
    /// Reflects `presentedMedia` only (NOT the dismiss-deferred
    /// `hidingMedia`), so it flips synchronously at dismiss start to
    /// trigger the matched-geo close animation.
    let activeID: UUID?
    /// Drives card opacity — the VISIBILITY toggle. Reflects
    /// `presentedMedia ?? hidingMedia`, so it stays set during the
    /// close animation. Without this, the card's image becomes
    /// visible mid-animation while the viewer's image is still
    /// shrinking back, producing a visible double-image effect.
    let visibleID: UUID?
    let onTap: (MediaPayload, UUID) -> Void

    /// Equatable comparison ignores `onTap` — closures aren't
    /// equatable, but the closure's identity is irrelevant for
    /// downstream view invalidation. What matters for invalidation is
    /// the two ids. Without this, `RootView.mediaTapHandler` (a
    /// computed property creating a fresh closure-bearing struct each
    /// body run) caused SwiftUI to consider the environment value
    /// "different" on every RootView re-render and cascade re-renders
    /// through every card's `MatchedGeometryModifier` — which in turn
    /// re-published frame preferences via `CardFrameKey`, mutating
    /// `sourceFrames` and re-invalidating RootView. The feedback loop
    /// stuttered the close animation. With Equatable, SwiftUI skips
    /// the env injection when only the closure changed.
    static func == (lhs: MediaTapHandler, rhs: MediaTapHandler) -> Bool {
        lhs.activeID == rhs.activeID && lhs.visibleID == rhs.visibleID
    }
}

/// Snapshot of "what's being shown in the viewer." Carries the
/// `sourceFrame` captured at tap time so the open/close animations
/// have a stable target frame even if the timeline scrolls or
/// re-layouts behind the viewer.
struct PresentedMedia: Hashable {
    let sourceID: UUID
    let payload: MediaPayload
    /// Source card's image-area frame at the moment of tap (global
    /// coords). Frozen — doesn't update if the card moves underneath.
    let sourceFrame: CGRect

    static func == (lhs: PresentedMedia, rhs: PresentedMedia) -> Bool {
        lhs.sourceID == rhs.sourceID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sourceID)
    }
}

/// PreferenceKey that bubbles each card's image-area frame (in global
/// coords) up to `CardFrameStore`. The viewer uses these to know where
/// to "zoom out from" on dismiss and "zoom in to" on open.
struct CardFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Phase F.1.2.zoomfix — single source of truth for the live card
/// frame map. **Plain reference type, NOT `@Observable`** — the only
/// reader is the tap-handler closure (which runs at tap time when the
/// dictionary is settled). Making the storage observable was the bug:
/// `RootView` had `@State sourceFrames` updated from
/// `.onPreferenceChange`, which churned the state and re-rendered the
/// entire screen on every layout pass — every card re-rendered, every
/// card republished its frame, the dict mutated again, RootView
/// re-rendered. Feedback loop scaled with card count, manifesting as
/// drag-down-to-dismiss "image duplicates and shakes" + "entire screen
/// flickers." Storing in a plain class lets `.onPreferenceChange`
/// write without invalidating any SwiftUI view subtree.
@MainActor
final class CardFrameStore {
    static let shared = CardFrameStore()
    var frames: [UUID: CGRect] = [:]
}

/// Environment-injected so cards (`KeepCard`, `NoteCard`) can pick up
/// the handler without parameters threading through `TimelineScreen` →
/// `CardsBoardView` / `StackedBoardView` → card. `RootView` sets it.
extension EnvironmentValues {
    @Entry var mediaTapHandler: MediaTapHandler? = nil
}

/// Modifier on each card's media area: publishes its global frame for
/// RootView's source-frame map, and toggles opacity to 0 while the
/// viewer is showing this card (so the source slot stays "empty" until
/// the close animation completes).
///
/// **No `matchedGeometryEffect`.** SwiftUI's matched-geo doesn't play
/// well with overlay-based presentation (the viewer ends up sliding in
/// from the side and dismissing-back rendered in the wrong z-layer).
/// The manual approach: the viewer interpolates its image's `.frame` +
/// `.position` between this card's frame and a fullscreen-fitted rect,
/// using its own `openProgress` state. Apple Photos works the same way.
struct MatchedGeometryModifier: ViewModifier {
    let handler: MediaTapHandler?
    let id: UUID

    func body(content: Content) -> some View {
        if let handler {
            content
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: CardFrameKey.self,
                            value: [id: geo.frame(in: .global)]
                        )
                    }
                }
                .opacity(handler.visibleID == id ? 0 : 1)
        } else {
            content
        }
    }
}
