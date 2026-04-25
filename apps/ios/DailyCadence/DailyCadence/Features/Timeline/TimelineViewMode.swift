import Foundation

/// How the Today screen is currently rendering its notes.
///
/// Matches the Timeline | Cards segmented toggle in
/// `design/claude-design-system/ui_kits/mobile/Timeline.jsx`.
enum TimelineViewMode: Hashable, CaseIterable, Identifiable {
    /// Chronological rail with dots — default.
    case timeline
    /// Google Keep-style 2-column card grid.
    case cards

    var id: Self { self }

    var title: String {
        switch self {
        case .timeline: return "Timeline"
        case .cards:    return "Cards"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: return "list.bullet"
        case .cards:    return "square.grid.2x2"
        }
    }
}
