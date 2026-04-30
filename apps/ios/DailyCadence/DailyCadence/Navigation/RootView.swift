import SwiftUI

/// The app's root container — swaps the visible feature screen based on the
/// current `RootTab` selection and pins the design-system `TabBar` to the
/// bottom via `safeAreaInset`.
///
/// Each feature screen owns its own `NavigationStack`, so each tab's
/// navigation stack is independent (iOS standard tab-bar behavior).
///
/// **Phase F.1.1b'.zoom — manual matched-geometry overlay.** Cards
/// publish their image-area frames via `CardFrameKey`; on tap, RootView
/// snapshots that frame onto `PresentedMedia` and animates
/// `openProgress` from 0 (image at source frame) to 1 (image at
/// fullscreen-fitted frame). The viewer interpolates the image's
/// `.frame` + `.position` manually between source and full. SwiftUI's
/// `matchedGeometryEffect` was tried but doesn't play well with overlay
/// presentation — the viewer would slide in from the side and the
/// close animation would render in the wrong z-layer.
struct RootView: View {
    @State private var selection: RootTab = .today

    /// Phase F.1.2.midnight — covers the "app was suspended across
    /// midnight" gap. `significantTimeChangeNotification` fires at
    /// midnight while the app is foreground; iOS may not deliver it
    /// reliably across suspension. On every active transition, ask the
    /// store to recompute — idempotent, no-ops when the day hasn't
    /// changed.
    @Environment(\.scenePhase) private var scenePhase

    /// Tracks keyboard visibility so the custom TabBar can hide while
    /// typing — the standard iOS pattern (Mail, Notes, Messages all do
    /// this). System `TabView` handles this automatically; our custom
    /// `safeAreaInset`-mounted TabBar doesn't, so we observe keyboard
    /// notifications and conditionally render the TabBar instead.
    @State private var keyboardVisible = false

    /// Drives the open animation + steady-state viewer. Set/cleared
    /// alongside `openProgress` for the matched-geo zoom feel.
    @State private var presentedMedia: PresentedMedia?

    /// Holds the same payload as `presentedMedia` during the close
    /// animation so the viewer overlay STAYS rendered (above the
    /// timeline + TabBar) while `openProgress` interpolates back to 0.
    /// Cleared on a delayed `Task` once the close animation is past.
    @State private var hidingMedia: PresentedMedia?

    /// 0 = image at source-card frame, 1 = image at fullscreen-fitted
    /// frame. Animated via `withAnimation` on present/dismiss to drive
    /// the manual zoom in `MediaViewerScreen`.
    @State private var openProgress: CGFloat = 0

    var body: some View {
        gatedContent
    }

    /// Auth + onboarding gate. Three terminal states once `isReady`:
    /// signed-out → `OnboardingScreen` (sign-in), signed-in and needs
    /// onboarding → `OnboardingFlow`, otherwise → app shell.
    ///
    /// "Needs onboarding" is the OR of two signals:
    /// - `!hasCompletedOnboarding` — device-local `UserDefaults` flag.
    ///   Goes false on a fresh install / new device, even for an
    ///   existing user.
    /// - `!auth.hasName` — server-side check via
    ///   `auth.users.raw_user_meta_data`. If we don't even know the
    ///   user's name, we definitely haven't onboarded them.
    ///
    /// The OR means a returning user on a new device skips onboarding
    /// (their names are already on the server), AND a fresh user who
    /// somehow had the flag set without going through the flow still
    /// gets shown it. Both edges covered.
    @ViewBuilder
    private var gatedContent: some View {
        let auth = AuthStore.shared
        if !auth.isReady {
            ZStack {
                Color.DS.bg1.ignoresSafeArea()
                ProgressView().tint(Color.DS.sage)
            }
        } else if auth.currentUserId == nil {
            OnboardingScreen()
        } else if !AppPreferencesStore.shared.hasCompletedOnboarding || !auth.hasName {
            OnboardingFlow()
        } else {
            appShell
        }
    }

    private var appShell: some View {
        content
            .environment(\.mediaTapHandler, mediaTapHandler)
            // Phase F.1.2.zoomfix — write to the non-observable
            // `CardFrameStore` singleton instead of a `@State` dict.
            // Storing in `@State` was the cause of the drag-dismiss
            // "image duplicates / screen flickers" bug — every layout
            // pass on every card published a frame preference, this
            // closure mutated the @State, RootView re-rendered, every
            // card re-rendered, and frames re-published. Feedback loop
            // scaled with card count. Plain class breaks the loop —
            // the only reader is the tap-handler closure below, which
            // runs at tap time when the dict is settled.
            .onPreferenceChange(CardFrameKey.self) { newFrames in
                CardFrameStore.shared.frames = newFrames
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Hide the TabBar while the keyboard is up — iOS Mail /
                // Notes / Messages all do this. A tab bar isn't useful
                // mid-type, and removing it from the safe-area inset
                // cleanly recovers the screen real estate so focused
                // fields + adjacent action buttons (the Delete Account
                // confirmation, future search bars, etc.) sit above the
                // keyboard without being sandwiched. System `TabView`
                // gets this for free; our custom TabBar needs the
                // observation in `keyboardVisible`.
                if !keyboardVisible {
                    TabBar(items: tabItems, selection: $selection)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                if let displayed = presentedMedia ?? hidingMedia {
                    MediaViewerScreen(
                        media: displayed.payload,
                        sourceFrame: displayed.sourceFrame,
                        openProgress: openProgress,
                        onDismiss: dismissViewer
                    )
                    // `.identity` so SwiftUI doesn't apply a default
                    // appearance transition over our manual frame
                    // interpolation. The viewer container materializes
                    // instantly; openProgress drives the visible zoom.
                    .transition(.identity)
                }
            }
            // Root-level tint propagates the user's chosen primary color to
            // all SwiftUI controls (buttons, links, progress indicators) via
            // the environment. Reading `Color.DS.sage` here makes RootView
            // observe `ThemeStore.shared.primary`; any theme change triggers
            // a re-render and the tint updates everywhere at once.
            .tint(Color.DS.sage)
            // Refetch the timeline on either auth changes (anon sign-in
            // completes asynchronously) or day changes (user navigates to
            // a different date via the header / swipe / picker). The id
            // tuple combines both; SwiftUI restarts the task when either
            // value changes. `hasLoaded` is the idempotency guard so the
            // task body bails out when a re-render fires the same id.
            .task(id: TimelineLoadKey(
                userId: AuthStore.shared.currentUserId,
                date: TimelineStore.shared.selectedDate
            )) {
                guard let userId = AuthStore.shared.currentUserId else { return }
                if !TimelineStore.shared.hasLoaded {
                    await TimelineStore.shared.load(userId: userId)
                }
                // Phase F.1.2.weekstrip — load the week-strip data
                // alongside the day's notes. Same auth + selectedDate
                // trigger; same-week navigations short-circuit inside
                // the store so this is idempotent.
                await WeekStripStore.shared.load(
                    userId: userId,
                    day: TimelineStore.shared.selectedDate
                )
                // Phase F.1.2.daymarks — bulk fetch of per-day emoji
                // markers. Set is small (most users have <50 marked
                // days), so a single load on launch + user-change
                // covers the whole UX. `hasLoaded` short-circuits
                // re-fires from selectedDate changes.
                if !DayMarkStore.shared.hasLoaded {
                    await DayMarkStore.shared.load(userId: userId)
                }
                // Phase F.1.2.pageflip — warm the cache for the days
                // adjacent to `selectedDate` so the timeline doesn't
                // show empty state while a day's notes load mid-
                // navigation. ±7 days covers the dial's week-swipes
                // (the new selection lands at exactly +7/-7 from the
                // current week's same weekday) AND casual day-to-day
                // navigation in either direction. Concurrent + best-
                // effort — prefetch failures are silent inside the
                // store; the next on-demand `load(userId:)` will
                // surface any real error.
                let cal = Calendar.current
                let center = TimelineStore.shared.selectedDate
                await withTaskGroup(of: Void.self) { group in
                    for offset in (-7...7) where offset != 0 {
                        guard let day = cal.date(byAdding: .day, value: offset, to: center) else { continue }
                        group.addTask {
                            await TimelineStore.shared.prefetch(userId: userId, day: day)
                        }
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    TimelineStore.shared.refreshCurrentDay()
                }
            }
            // Keyboard observers drive `keyboardVisible`, which
            // toggles the TabBar visibility in the bottom safeAreaInset.
            // `0.25s ease` matches iOS's default keyboard animation
            // curve so the TabBar slide is visually in sync with the
            // keyboard rise/fall.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    keyboardVisible = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    keyboardVisible = false
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .today:
            // Pass the tab-switch closure so the top-bar gear can
            // jump straight to Settings (matches what most modern
            // apps do — gear in upper-right is a shortcut, not a
            // navigation push).
            TimelineScreen(onOpenSettings: { selection = .settings })
        case .calendar: CalendarScreen()
        case .progress: DashboardScreen()
        case .library:  LibraryScreen()
        case .settings: SettingsScreen()
        }
    }

    // MARK: - Media viewer

    /// Handler injected into `EnvironmentValues.mediaTapHandler` so cards
    /// can fire `onTap` and have RootView flip into presentation. The
    /// `activeID`/`visibleID` split keeps the source card invisible
    /// across the entire close animation.
    private var mediaTapHandler: MediaTapHandler {
        MediaTapHandler(
            activeID: presentedMedia?.sourceID,
            visibleID: (presentedMedia ?? hidingMedia)?.sourceID
        ) { payload, sourceID in
            // Snapshot the source frame at tap time — frozen for the
            // open AND close animations so timeline scrolling /
            // re-layout behind the viewer doesn't move our target.
            // Fall back to .zero if the card hasn't reported a frame
            // yet; first-frame zoom will be slightly off but won't
            // crash, and subsequent renders fill in.
            let frame = CardFrameStore.shared.frames[sourceID] ?? .zero
            presentedMedia = PresentedMedia(
                sourceID: sourceID,
                payload: payload,
                sourceFrame: frame
            )
            withAnimation(.smooth(duration: 0.5)) {
                openProgress = 1
            }
        }
    }

    /// Closes the viewer with the manual zoom-back. Keeps the overlay
    /// rendered via `hidingMedia` for the animation duration so the
    /// close runs in this overlay layer (above timeline + TabBar).
    /// `.smooth(duration: 0.5)` matched on both directions removes the
    /// spring-physics asymmetry that made open feel faster than close;
    /// the 510 ms deferred clear is just past the animation's end.
    private func dismissViewer() {
        hidingMedia = presentedMedia
        presentedMedia = nil
        withAnimation(.smooth(duration: 0.5)) {
            openProgress = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(510))
            hidingMedia = nil
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

/// Composite id for the timeline's load `.task`. SwiftUI restarts the task
/// whenever any field changes, so the timeline re-fetches on either auth
/// transitions or selected-day changes — exactly the two events that
/// invalidate the currently-displayed list.
private struct TimelineLoadKey: Equatable {
    let userId: UUID?
    let date: Date
}

#Preview("Light") {
    RootView()
}

#Preview("Dark") {
    RootView().preferredColorScheme(.dark)
}
