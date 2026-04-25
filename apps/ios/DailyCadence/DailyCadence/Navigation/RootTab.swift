import SwiftUI

/// The five top-level tabs of DailyCadence.
///
/// Choice of five matches the design system's 5-column `.tabbar` grid.
/// Order and roster is a Phase 1 first pass — easy to adjust once we have
/// real usage data.
enum RootTab: Hashable, CaseIterable, Identifiable {
    /// The daily timeline — primary surface.
    case today
    /// Monthly calendar overview of logged activity.
    case calendar
    /// Progress dashboard — widgets + links to exercise charts.
    case progress
    /// All-time notes browser (Google Keep-style filterable grid).
    case library
    /// App settings, profile, preferences.
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .today:    return "Today"
        case .calendar: return "Calendar"
        case .progress: return "Progress"
        case .library:  return "Library"
        case .settings: return "Settings"
        }
    }

    /// SF Symbol placeholder. Swap to the design system's custom line icons
    /// (see `design/claude-design-system/preview/icons.html`) once extracted.
    var systemImage: String {
        switch self {
        case .today:    return "list.bullet"
        case .calendar: return "calendar"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .library:  return "square.grid.2x2"
        case .settings: return "gearshape"
        }
    }
}
