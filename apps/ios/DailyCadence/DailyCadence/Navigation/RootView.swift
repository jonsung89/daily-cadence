import SwiftUI

/// The app's root container — swaps the visible feature screen based on the
/// current `RootTab` selection and pins the design-system `TabBar` to the
/// bottom via `safeAreaInset`.
///
/// Each feature screen owns its own `NavigationStack`, so each tab's
/// navigation stack is independent (iOS standard tab-bar behavior).
struct RootView: View {
    @State private var selection: RootTab = .today

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TabBar(items: tabItems, selection: $selection)
            }
            // Root-level tint propagates the user's chosen primary color to
            // all SwiftUI controls (buttons, links, progress indicators) via
            // the environment. Reading `Color.DS.sage` here makes RootView
            // observe `ThemeStore.shared.primary`; any theme change triggers
            // a re-render and the tint updates everywhere at once.
            .tint(Color.DS.sage)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .today:    TimelineScreen()
        case .calendar: CalendarScreen()
        case .progress: DashboardScreen()
        case .library:  LibraryScreen()
        case .settings: SettingsScreen()
        }
    }

    /// Tab items for the bottom bar. The `.today` slot's label + icon
    /// mirror the user's chosen default view (Timeline or Board) from
    /// `AppPreferencesStore.shared.defaultTodayView` — Phase E.5.2 — so
    /// the tab communicates what they'll see when they tap it. Reading
    /// the preference inside `body` registers RootView as an observer,
    /// so changing the default in Settings updates the tab live.
    private var tabItems: [TabBarItem<RootTab>] {
        let defaultView = AppPreferencesStore.shared.defaultTodayView
        return RootTab.allCases.map { tab in
            switch tab {
            case .today:
                return TabBarItem(
                    id: tab,
                    title: defaultView.title,
                    systemImage: defaultView.systemImage
                )
            default:
                return TabBarItem(
                    id: tab,
                    title: tab.title,
                    systemImage: tab.systemImage
                )
            }
        }
    }
}

#Preview("Light") {
    RootView()
}

#Preview("Dark") {
    RootView().preferredColorScheme(.dark)
}
