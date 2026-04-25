import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The Daily Timeline — primary surface of DailyCadence.
///
/// Matches wireframe Screen 2 + the Timeline.jsx prototype in the design
/// system's mobile UI kit:
/// - Top bar: day-name caption + big serif date, settings icon on the right
/// - Segmented view switcher (Timeline | Board)
/// - Timeline view: vertical rail of `NoteCard`s connected by a sage-dotted line
/// - Board view: 2-column Keep-style masonry of `KeepCard`s
/// - FAB floating at bottom-right to open the note editor
///
/// Currently backed by `MockNotes.today`. Swap to real Supabase-backed data
/// once the `notes` table + Swift SDK are wired (see `docs/PROGRESS.md`).
struct TimelineScreen: View {
    @State private var viewMode: TimelineViewMode = AppPreferencesStore.shared.defaultTodayView
    @State private var boardLayout: BoardLayoutMode = .cards
    @State private var isEditorPresented = false

    /// Drives the photo/video editor flow when the user picks
    /// "Photo or video" from the FAB menu (Phase E.3).
    @State private var isMediaPickerPresented = false
    @State private var mediaPickerItem: PhotosPickerItem?
    @State private var isMediaEditorPresented = false

    /// Read-through to `TimelineStore.shared.notes`. Reading inside `body`
    /// registers this view as an observer of the @Observable store, so any
    /// `add(_:)` call re-renders the timeline automatically.
    private var notes: [MockNote] { TimelineStore.shared.notes }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 12)

                    segmentedToggle
                        .padding(.horizontal, 20)
                        .padding(.bottom, viewMode == .board ? 12 : 16)

                    if viewMode == .board {
                        boardLayoutToggle
                            .padding(.horizontal, 20)
                            .padding(.bottom, cardsOrderBarVisible ? 8 : 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if cardsOrderBarVisible {
                        resetOrderRow
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    content
                        .padding(.horizontal, horizontalPadding(for: viewMode))
                }
            }
            // Phase E.5.3 — iOS 17+ `.contentMargins(.bottom, _:, for: .scrollContent)`
            // reserves a bottom buffer in the scrollable content area so
            // the persistent FAB never overlaps the last card. 120pt
            // covers the FAB's 56pt frame + 16pt bottom padding + ~48pt
            // breathing room for the shadow. This is the iOS-native
            // pattern (Apple Mail, Reminders, Google Keep iOS all keep
            // the FAB persistent and rely on content insets); the
            // hide-on-scroll trick is more Material Design than UIKit.
            .contentMargins(.bottom, 120, for: .scrollContent)
            .background(Color.DS.bg1)
            .toolbar(.hidden, for: .navigationBar)
            .animation(.easeOut(duration: 0.18), value: viewMode)
        }
        .overlay(alignment: .bottomTrailing) {
            // Menu attached directly to the FAB — popup anchors to the
            // button itself rather than sliding up from the screen
            // bottom (the prior `.confirmationDialog` placement felt
            // disconnected from a bottom-right FAB). On iOS 26 the Menu
            // gets the standard glass-styled popover.
            //
            // FAB stays persistent; the ScrollView's `.contentMargins`
            // reserves a 120pt bottom buffer so the last card never
            // ends up underneath the button.
            Menu {
                Button {
                    isEditorPresented = true
                } label: {
                    Label("Text Note", systemImage: "note.text")
                }
                Button {
                    isMediaPickerPresented = true
                } label: {
                    Label("Photo or Video", systemImage: "photo.on.rectangle")
                }
            } label: {
                FABAppearance()
            }
            .accessibilityLabel("Add a note")
            .padding(.trailing, 20)
            .padding(.bottom, 16)
        }
        .photosPicker(
            isPresented: $isMediaPickerPresented,
            selection: $mediaPickerItem,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        )
        .onChange(of: mediaPickerItem) { _, newItem in
            // PhotosPicker dismisses on selection — open the media editor
            // sheet so the user can add a caption + type before saving.
            if newItem != nil { isMediaEditorPresented = true }
        }
        .sheet(isPresented: $isEditorPresented) {
            NoteEditorScreen()
        }
        .sheet(isPresented: $isMediaEditorPresented, onDismiss: { mediaPickerItem = nil }) {
            MediaNoteEditorScreen(initialItem: mediaPickerItem)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dayOfWeek)
                    .font(.DS.sans(size: 11, weight: .bold))
                    .tracking(0.88)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.DS.fg2)
                Text(dateTitle)
                    .font(.DS.serif(size: 28, weight: .bold))
                    .tracking(-0.56)  // -0.02em at 28pt
                    .foregroundStyle(Color.DS.ink)
            }
            Spacer(minLength: 12)
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.DS.ink)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var dayOfWeek: String {
        Date.now.formatted(.dateTime.weekday(.wide))
    }

    private var dateTitle: String {
        Date.now.formatted(.dateTime.month(.wide).day())
    }

    // MARK: - Segmented toggles

    private var segmentedToggle: some View {
        Segmented(
            options: orderedViewModes.map { mode in
                SegmentedOption(id: mode, title: mode.title, systemImage: mode.systemImage)
            },
            selection: $viewMode
        )
    }

    /// Order the Timeline / Board segments so the user's chosen default
    /// sits in the first (leftmost) slot — Phase E.5.4. The non-default
    /// view follows. Reading `AppPreferencesStore.shared.defaultTodayView`
    /// inside `body` registers the screen as an observer, so flipping
    /// the default in Settings re-orders the toggle live.
    private var orderedViewModes: [TimelineViewMode] {
        let defaultMode = AppPreferencesStore.shared.defaultTodayView
        return [defaultMode] + TimelineViewMode.allCases.filter { $0 != defaultMode }
    }

    /// Sub-toggle shown only when `viewMode == .board`. Lets the user pick how
    /// cards are organized: stacked by type, grouped into sections by type,
    /// or free-form (current 2-col masonry).
    private var boardLayoutToggle: some View {
        Segmented(
            options: BoardLayoutMode.allCases.map { mode in
                SegmentedOption(id: mode, title: mode.title, systemImage: mode.systemImage)
            },
            selection: $boardLayout
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if notes.isEmpty {
            emptyState
        } else {
            switch viewMode {
            case .timeline:
                timelineView
            case .board:
                boardContent
            }
        }
    }

    /// Dispatches Board rendering based on `boardLayout`.
    @ViewBuilder
    private var boardContent: some View {
        switch boardLayout {
        case .cards:
            cardsBoardGrid
        case .grouped:
            groupedView
        case .stacked:
            StackedBoardView(groups: groupedNotes)
        }
    }

    /// Free-layout 2-col masonry with drag-to-reorder.
    ///
    /// We use `.onDrag(_:preview:)` (rather than the newer `.draggable`)
    /// because its data closure runs **at drag start** — that's the hook
    /// for publishing the dragging id to `DragSessionStore.shared`
    /// synchronously. `.draggable` only takes an `@autoclosure` payload
    /// expression, which can't carry side effects in a way that runs
    /// once when the drag begins.
    ///
    /// `.onDrop(of:delegate:)` + `NoteReorderDropDelegate` returns
    /// `DropProposal(.move)` from `dropUpdated` (no green "+" badge) and
    /// performs the live reorder from `dropEntered`. `performDrop` is a
    /// fallback for cases `dropEntered` missed.
    ///
    /// `.contentShape(.dragPreview, RoundedRectangle(...))` clips the
    /// long-press lift preview to the card's rounded corners.
    private var cardsBoardGrid: some View {
        let orderedNotes = CardsViewOrderStore.shared.sorted(notes)
        // Read these from the store inside the body so the views below
        // re-render automatically when the drag session changes (the
        // store is `@Observable`).
        let draggingId = DragSessionStore.shared.draggingNoteId
        let dropTargetId = DragSessionStore.shared.currentDropTargetId
        return KeepGrid(items: orderedNotes) { note in
            let isSourceOfDrag = draggingId == note.id
            let isLiveDropTarget = dropTargetId == note.id && !isSourceOfDrag
            KeepCard(note: note)
                // Fade the source card while it's being dragged so the
                // user sees the drag "lifted" and the live-reflow's
                // shifting cards aren't competing visually with a
                // double-rendered original.
                .opacity(isSourceOfDrag ? 0.35 : 1)
                // Subtle highlight on whichever card the finger is
                // currently over — explicit "this is where it'll land"
                // cue. Uses the user's primary theme color so it picks
                // up the active palette.
                .overlay {
                    if isLiveDropTarget {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.DS.sage, lineWidth: 2)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: isSourceOfDrag)
                .animation(.easeOut(duration: 0.18), value: isLiveDropTarget)
                .contentShape(
                    .dragPreview,
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .onDrag {
                    // Runs once at drag start. Two responsibilities:
                    //   1. Clear any leftover state from a previous drag
                    //      that ended without a `performDrop` callback —
                    //      iOS filters the source view as a drop target,
                    //      so dropping precisely on yourself never
                    //      reaches our delegate, leaving the source's
                    //      fade lingering until the next drag.
                    //   2. Publish the new dragging id so
                    //      `NoteReorderDropDelegate.dropEntered` reads
                    //      it synchronously (no async
                    //      `NSItemProvider.loadObject` round-trip).
                    DragSessionStore.shared.endSession()
                    DragSessionStore.shared.draggingNoteId = note.id
                    return NSItemProvider(object: note.id.uuidString as NSString)
                } preview: {
                    KeepCard(note: note)
                        .frame(maxWidth: 180)
                        .opacity(0.85)
                        .contentShape(
                            .dragPreview,
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .onDrop(
                    of: [.text],
                    delegate: NoteReorderDropDelegate(
                        targetNote: note,
                        allNotes: notes
                    )
                )
        }
    }

    /// Visible whenever the user is on the Free Board layout AND has
    /// reordered at least once. Empty state hides the reset.
    private var cardsOrderBarVisible: Bool {
        viewMode == .board
            && boardLayout == .cards
            && CardsViewOrderStore.shared.hasCustomOrder
    }

    /// "Reset to chronological" pill — restores the default oldest-→-newest
    /// order from `TimelineStore`.
    private var resetOrderRow: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    CardsViewOrderStore.shared.reset()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Reset order")
                        .font(.DS.sans(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.DS.fg2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous).fill(Color.DS.bg2)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.DS.border1, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset Free order to chronological")
        }
    }

    private func horizontalPadding(for mode: TimelineViewMode) -> CGFloat {
        switch mode {
        case .timeline: return 8    // timeline items carry their own left gutter
        case .board:    return 12   // matches `KeepGrid.spacing` for uniform rhythm
        }
    }

    // MARK: - Grouped view

    /// Cards organized into sections by `NoteType`. Sections appear in
    /// `NoteType.allCases` order so the layout stays stable as notes are
    /// added or removed (sections without any notes are filtered out).
    private var groupedView: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(groupedNotes, id: \.type) { group in
                VStack(alignment: .leading, spacing: 10) {
                    groupHeader(type: group.type, count: group.notes.count)
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                        ],
                        spacing: 8
                    ) {
                        ForEach(group.notes) { note in
                            KeepCard(note: note)
                        }
                    }
                }
            }
        }
    }

    private func groupHeader(type: NoteType, count: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(type.color)
                .frame(width: 8, height: 8)
            Text(type.title)
                .font(.DS.sans(size: 11, weight: .bold))
                .tracking(0.88)  // 0.08em at 11pt
                .textCase(.uppercase)
                .foregroundStyle(type.color)
            Text("\(count)")
                .font(.DS.sans(size: 11, weight: .medium))
                .foregroundStyle(Color.DS.fg2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    /// Notes grouped by `NoteType`, preserving the canonical type ordering.
    /// Empty types are filtered so the layout doesn't render hollow headers.
    private var groupedNotes: [(type: NoteType, notes: [MockNote])] {
        let byType = Dictionary(grouping: notes, by: \.type)
        return NoteType.allCases.compactMap { type in
            guard let group = byType[type], !group.isEmpty else { return nil }
            return (type, group)
        }
    }

    private var timelineView: some View {
        VStack(spacing: 0) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                TimelineItem(
                    time: note.time,
                    type: note.type,
                    lineStyle: lineStyle(for: index)
                ) {
                    NoteCard(
                        type: note.type,
                        title: note.timelineTitle,
                        message: note.timelineMessage,
                        background: note.resolvedBackgroundStyle,
                        titleStyle: note.titleStyle,
                        media: note.mediaPayload
                    )
                }
            }
        }
    }

    private func lineStyle(for index: Int) -> TimelineLineStyle {
        if notes.count == 1 { return .dotOnly }
        if index == 0 { return .belowDotOnly }
        if index == notes.count - 1 { return .aboveDotOnly }
        return .full
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.DS.fg2)
            Text("Nothing yet")
                .font(.DS.h3)
                .foregroundStyle(Color.DS.ink)
            Text("Tap + to add the first note of your day.")
                .font(.DS.small)
                .foregroundStyle(Color.DS.fg2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Actions

    private func openSettings() {
        // TODO: push the Settings screen once navigation destinations are wired.
        // (For Phase C: Settings is reached via the bottom tab bar; this top
        // button is a future quick-access shortcut.)
    }
}

// MARK: - Previews

#Preview("Timeline view, light") {
    TimelineScreen()
}

#Preview("Timeline view, dark") {
    TimelineScreen()
        .preferredColorScheme(.dark)
}
