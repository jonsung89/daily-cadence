import Foundation

/// How the Today screen is currently rendering its notes.
///
/// Two perspectives on the same data:
/// - **Timeline** — chronological vertical rail with sage-dotted markers.
///   Emphasizes *when* things happened.
/// - **Board** — Google Keep-style 2-column masonry of varied cards.
///   Emphasizes *what* you logged. Pairs with future drag-to-reorder.
///
/// Mirrors the `Timeline | Cards` segmented toggle in
/// `design/claude-design-system/ui_kits/mobile/Timeline.jsx` — we picked
/// "Board" over "Cards" because Cards is generic (every note is on a card)
/// and "Board" matches the pinboard-of-moments feel of the masonry layout.
enum TimelineViewMode: Hashable, CaseIterable, Identifiable {
    /// Chronological rail with dots — default.
    case timeline
    /// Google Keep-style 2-column masonry — pinboard of varied note cards.
    case board

    var id: Self { self }

    var title: String {
        switch self {
        case .timeline: return "Timeline"
        case .board:    return "Board"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: return "list.bullet"
        case .board:    return "square.grid.2x2"
        }
    }
}
