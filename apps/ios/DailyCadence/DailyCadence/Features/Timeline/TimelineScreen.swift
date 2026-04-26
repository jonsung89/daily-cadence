import SwiftUI
import PhotosUI

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

    /// The note id the user has asked to delete (Phase E.5.15). When
    /// non-nil, drives the `.confirmationDialog`. The card's
    /// `.contextMenu` Delete action sets this; user confirmation in
    /// the dialog calls `TimelineStore.shared.delete(noteId:)`.
    @State private var pendingDeleteId: UUID? = nil

    /// Read-through to `TimelineStore.shared.notes`. Reading inside `body`
    /// registers this view as an observer of the @Observable store, so any
    /// `add(_:)` call re-renders the timeline automatically.
    private var notes: [MockNote] { TimelineStore.shared.notes }

    /// Notes the user has pinned (Phase E.5.15). Reading
    /// `PinStore.shared.pinnedIds` inside `body` registers this view as
    /// an observer so the Pinned section appears/disappears live as the
    /// user toggles pins.
    private var pinnedNotes: [MockNote] {
        let pinned = PinStore.shared.pinnedIds
        return notes.filter { pinned.contains($0.id) }
    }

    /// The complement — everything not pinned. Used as the input to the
    /// Board sub-mode layouts so a pinned note doesn't appear twice.
    private var unpinnedNotes: [MockNote] {
        let pinned = PinStore.shared.pinnedIds
        return notes.filter { !pinned.contains($0.id) }
    }

    /// Boolean projection of `pendingDeleteId` for the dialog's
    /// `isPresented:` binding (`.confirmationDialog` doesn't take an
    /// optional binding directly).
    private var pendingDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteId != nil },
            set: { if !$0 { pendingDeleteId = nil } }
        )
    }

    /// Closure passed into every card via the `onRequestDelete:` parameter.
    /// Cards call this from their `.contextMenu` Delete action; this just
    /// arms the confirmation dialog.
    private func requestDelete(_ noteId: UUID) {
        pendingDeleteId = noteId
    }

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
                        .padding(.bottom, cardsOrderBarVisible ? 12 : 16)

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
            .animation(.easeOut(duration: 0.18), value: boardLayout)
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
            // SwiftUI's `Menu` anchored to a bottom-trailing FAB opens
            // upward and orders items closest-to-anchor first (so the
            // last-declared item renders at the visual TOP of the
            // popup). Text Note is the more frequent action — putting
            // it last in source places it on top, matching Apple Mail's
            // compose menu ordering.
            Menu {
                Button {
                    isMediaPickerPresented = true
                } label: {
                    Label("Photo or Video", systemImage: "photo.on.rectangle")
                }
                Button {
                    isEditorPresented = true
                } label: {
                    Label("Text Note", systemImage: "note.text")
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
        .sheet(
            isPresented: $isEditorPresented
        ) {
            NoteEditorScreen()
        }
        .sheet(
            isPresented: $isMediaEditorPresented,
            onDismiss: {
                mediaPickerItem = nil
            }
        ) {
            MediaNoteEditorScreen(initialItem: mediaPickerItem)
        }
        // Phase E.5.17 — delete confirmation uses `.alert` (centered
        // modal) instead of `.confirmationDialog` (bottom action sheet).
        // For irreversible single-item destruction Apple consistently
        // uses an alert (Notes / Photos / Calendar / Reminders all do);
        // action sheets are reserved for multi-option pickers.
        .alert(
            "Delete this note?",
            isPresented: pendingDeletePresented,
            presenting: pendingDeleteId
        ) { id in
            Button("Delete", role: .destructive) {
                withAnimation(.easeOut(duration: 0.2)) {
                    TimelineStore.shared.delete(noteId: id)
                }
                pendingDeleteId = nil
            }
            Button("Keep", role: .cancel) {
                pendingDeleteId = nil
            }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
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
            // Phase E.5.13 — Board sub-mode picker moved from an inline
            // segmented row into a top-right toolbar Menu (Apple Files /
            // Photos pattern). Hidden in Timeline view (no sub-modes).
            // Icon reflects the active sub-mode so the user has a visual
            // cue at a glance without opening the menu.
            if viewMode == .board {
                boardSubModeMenu
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
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

    /// Top-right Menu picker for the Board sub-mode (Cards / Stack /
    /// Group). Uses SwiftUI's `Picker` inside a `Menu` so the active
    /// option auto-renders with a checkmark — native iOS pattern.
    private var boardSubModeMenu: some View {
        Menu {
            Picker("Board layout", selection: $boardLayout) {
                ForEach(BoardLayoutMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
        } label: {
            Image(systemName: boardLayout.systemImage)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.DS.ink)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Board layout — \(boardLayout.title)")
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

    /// Dispatches Board rendering based on `boardLayout`. Phase E.5.15
    /// inserts the Pinned section at the top of every sub-mode (when any
    /// note is pinned); the sub-mode-specific layout below it sees only
    /// the unpinned subset, so a pinned note never appears twice.
    @ViewBuilder
    private var boardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !pinnedNotes.isEmpty {
                pinnedSection
            }
            switch boardLayout {
            case .cards:
                cardsBoardGrid
            case .grouped:
                groupedView
            case .stacked:
                StackedBoardView(
                    groups: groupedNotes,
                    onRequestDelete: { requestDelete($0) }
                )
            }
        }
    }

    /// The "Pinned" section rendered at the top of each Board sub-mode
    /// when any note is pinned (Phase E.5.15).
    ///
    /// **Layout-per-mode.** For Cards and Stack the pinned cards render
    /// in a 2-col masonry — pinned notes are the user's "important now"
    /// list, and a flat masonry surfaces them clearly without the per-
    /// type stacking abstraction (you want pinned items immediately
    /// readable, not collapsed into a pile). For Group the pinned cards
    /// render in a horizontal scroll rail to match Group's all-rails
    /// visual rhythm.
    ///
    /// **Drag-to-reorder is intentionally not wired** for the pinned
    /// section in Phase 1 — pinned items keep chronological order. To
    /// rearrange pinned items the user can unpin and re-pin in the
    /// desired order. (Apple Notes' pinned section behaves the same
    /// way — sorted automatically, not user-reorderable.)
    @ViewBuilder
    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.DS.honey)
                Text("Pinned")
                    .font(.DS.sans(size: 11, weight: .bold))
                    .tracking(0.88)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.DS.honey)
                Text("\(pinnedNotes.count)")
                    .font(.DS.sans(size: 11, weight: .medium))
                    .foregroundStyle(Color.DS.fg2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            if boardLayout == .grouped {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(pinnedNotes) { note in
                            KeepCard(note: note, onRequestDelete: { requestDelete($0.id) })
                                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                                    width * 0.55
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            } else {
                KeepGrid(items: pinnedNotes) { note in
                    KeepCard(note: note, onRequestDelete: { requestDelete($0.id) })
                }
            }
        }
        .padding(.bottom, 4)
    }

    /// Cards-layout 2-col masonry, pure SwiftUI.
    ///
    /// Reorder uses `.draggable` + `.dropDestination` (iOS system drag,
    /// arbitrates cleanly with the parent `ScrollView`'s pan); masonry
    /// is a custom `Layout` that measures and places each card in the
    /// same render context. See `CardsBoardView` for the rationale on
    /// why this replaced the previous `UICollectionView` bridge.
    private var cardsBoardGrid: some View {
        CardsBoardView(
            notes: CardsViewOrderStore.shared.sorted(unpinnedNotes),
            onRequestDelete: requestDelete
        )
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
    ///
    /// **Phase E.5.11 — horizontal rail per section.** Each section is a
    /// horizontal `ScrollView` of cards (Apple Music / App Store rail
    /// pattern) instead of a 2-col vertical grid. Trade-offs:
    ///
    /// - Carves out a meaningfully different role from Stack (compact
    ///   collapsed glance) and Cards (free 2-col masonry) — Group is now
    ///   "all types visible at once, swipe each row to browse deep
    ///   types" without one busy type pushing every other type off screen.
    /// - Cards use a uniform width (~55% of the container, so 2 fit per
    ///   screen with a peek of the third — visual affordance for "more
    ///   to swipe"). Heights stay intrinsic per card, capped by the
    ///   existing `KeepCard.maxHeight`. Section height = tallest card.
    /// - `.scrollTargetBehavior(.viewAligned)` snaps the scroll to card
    ///   boundaries so flicks land cleanly.
    private var groupedView: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(groupedNotes, id: \.type) { group in
                VStack(alignment: .leading, spacing: 10) {
                    groupHeader(type: group.type, count: group.notes.count)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(group.notes) { note in
                                KeepCard(note: note, onRequestDelete: { requestDelete($0.id) })
                                    // ~55% of the visible scroll width:
                                    // shows ~2 cards with a peek of the
                                    // next so the user knows the rail
                                    // is scrollable. iOS 17 closure form
                                    // keeps this responsive across
                                    // device sizes.
                                    .containerRelativeFrame(
                                        .horizontal,
                                        alignment: .leading
                                    ) { width, _ in
                                        width * 0.55
                                    }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
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
    /// Phase E.5.15 — operates on `unpinnedNotes` so pinned items don't
    /// double up between the Pinned section and their type grouping.
    private var groupedNotes: [(type: NoteType, notes: [MockNote])] {
        let byType = Dictionary(grouping: unpinnedNotes, by: \.type)
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
                        media: note.mediaPayload,
                        noteId: note.id,
                        onRequestDelete: requestDelete
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
