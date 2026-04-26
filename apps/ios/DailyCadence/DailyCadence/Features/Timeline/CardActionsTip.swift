import SwiftUI
import TipKit

/// First-launch discoverability hint for the long-press → context menu
/// affordance on cards.
///
/// **Why a tip.** Pin and Delete are reachable only via long-press on a
/// card; users who haven't seen the iOS context-menu pattern elsewhere
/// can miss them entirely. A `TipKit` popover is the iOS-canonical way
/// to surface a non-obvious gesture without permanent chrome — it
/// auto-dismisses after the user uses the feature, so first-time
/// confusion is solved without nagging power users.
///
/// **Display rule.** The tip becomes invalid as soon as the user
/// actually uses the menu (donates `userDidUseContextMenu`), so it
/// disappears the first time they pin or delete a card. There's no
/// per-launch nag — TipKit also caps display frequency via the
/// `Tips.configure` call in `DailyCadenceApp`.
///
/// **Anchored** to the Timeline/Board segmented toggle, an always-
/// visible element near the cards. The tip text — "Touch and hold any
/// card…" — carries the gesture description; the popover doesn't need
/// to point at a specific card (which would be fragile across view
/// modes and reorder).
struct CardActionsTip: Tip {
    static let userDidUseContextMenu = Event(id: "card.actions.userDidUseContextMenu")

    var title: Text {
        Text("Pin or delete a card")
    }

    var message: Text? {
        Text("Touch and hold any card to see options.")
    }

    var image: Image? {
        Image(systemName: "hand.tap.fill")
    }

    var rules: [Rule] {
        [
            // Disqualify the tip the moment the user has used the menu
            // at least once. `donations.isEmpty` flips to `false` after
            // the first pin/delete via `.contextMenu`.
            #Rule(Self.userDidUseContextMenu) { $0.donations.isEmpty }
        ]
    }
}
