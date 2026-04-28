import SwiftUI
import PhotosUI
import TipKit

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

    /// Phase F.1.1b'.camera — drives the camera capture flow when the
    /// user picks "Take Photo or Video" from the FAB menu. The captured
    /// asset (image OR video URL) seeds `pendingCapture`; the editor
    /// opens with that as its initial source.
    @State private var isCameraPresented = false
    @State private var pendingCapture: MediaNoteEditorScreen.InitialMedia?

    /// Phase F.1.2.cameraflow — flips to true inside `CameraPicker.onPick`
    /// when the user accepts a capture. Read in `.fullScreenCover.onDismiss`
    /// to trigger the editor sheet ONCE the camera cover has fully
    /// dismissed. UIKit's modal stack rejects "present sheet while
    /// dismissing cover" — without this defer, the first-ever capture
    /// silently fails to open the editor (the sheet's `isPresented`
    /// flips but UIKit ignores it because a dismissal is in flight),
    /// and the user has to cancel + re-capture.
    @State private var presentEditorAfterCameraDismiss = false

    /// The note id the user has asked to delete (Phase E.5.15). When
    /// non-nil, drives the `.confirmationDialog`. The card's
    /// `.contextMenu` Delete action sets this; user confirmation in
    /// the dialog calls `TimelineStore.shared.delete(noteId:)`.
    @State private var pendingDeleteId: UUID? = nil

    /// Phase F.1.2.caption — id of the media note whose caption the
    /// user is editing. When non-nil, presents `CaptionEditSheet`. On
    /// save, the sheet's callback reconstructs the `MockNote` with an
    /// updated payload and forwards to `TimelineStore.update`.
    @State private var editingCaptionNoteId: UUID? = nil

    /// Phase F.1.0 — note the user has tapped to view+edit. When
    /// non-nil, presents `NoteEditorScreen(editing:)` as a sheet.
    /// Tapped from `NoteCard` / `KeepCard`'s `onTap` closures via
    /// `requestEdit(_:)`, which also filters out non-text variants
    /// (their editing flow isn't built yet).
    @State private var editingNote: MockNote? = nil

    /// First-launch discoverability hint for the long-press → context
    /// menu affordance. Auto-dismisses the first time the user pins or
    /// deletes a card via the menu (see `CardActionsTip`).
    private let cardActionsTip = CardActionsTip()

    /// Date picker sheet presentation. Tapping the header date column
    /// opens a graphical `DatePicker` so the user can jump to any day.
    @State private var isDatePickerPresented = false

    /// Phase F.1.1b'.zoom — media viewer state lives at `RootView` so
    /// the viewer overlay can render above the TabBar (which is
    /// mounted via `safeAreaInset` at RootView level). The handler
    /// is injected through environment; cards read it directly.
    @Environment(\.mediaTapHandler) private var mediaTapHandler

    /// Read-through to `TimelineStore.shared.notes`. Reading inside `body`
    /// registers this view as an observer of the @Observable store, so any
    /// `add(_:)` call re-renders the timeline automatically.
    private var notes: [MockNote] { TimelineStore.shared.notes }

    /// `true` while the initial / day-switch fetch is in flight. Drives
    /// the thin `LoadingBar` overlay at the top of the timeline.
    private var isLoadingNotes: Bool { !TimelineStore.shared.hasLoaded }

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

    /// Boolean projection of `editingCaptionNoteId` for the
    /// `CaptionEditSheet`'s `isPresented:` binding.
    private var editingCaptionPresented: Binding<Bool> {
        Binding(
            get: { editingCaptionNoteId != nil },
            set: { if !$0 { editingCaptionNoteId = nil } }
        )
    }

    /// Closure passed into every card via the `onRequestDelete:` parameter.
    /// Cards call this from their `.contextMenu` Delete action; this just
    /// arms the confirmation dialog.
    private func requestDelete(_ noteId: UUID) {
        pendingDeleteId = noteId
    }

    /// Phase F.1.2.caption — closure passed to media cards' long-press
    /// menu via `onRequestEditCaption:`. Arms the caption-edit sheet.
    private func requestEditCaption(_ noteId: UUID) {
        editingCaptionNoteId = noteId
    }

    /// Reconstructs the media note with the user's edited caption and
    /// forwards to `TimelineStore.update`. No-op if the note vanished
    /// between menu open and save (deleted in another tab, etc.).
    private func saveCaption(noteId: UUID, newCaption: String?) {
        guard let note = TimelineStore.shared.notes.first(where: { $0.id == noteId }),
              let payload = note.mediaPayload
        else { return }
        let updatedPayload = MediaPayload(
            kind: payload.kind,
            data: payload.data,
            posterData: payload.posterData,
            thumbnailData: payload.thumbnailData,
            aspectRatio: payload.aspectRatio,
            caption: newCaption,
            capturedAt: payload.capturedAt,
            ref: payload.ref,
            posterRef: payload.posterRef,
            thumbnailRef: payload.thumbnailRef
        )
        let updated = MockNote(
            id: note.id,
            occurredAt: note.occurredAt,
            type: note.type,
            content: .media(updatedPayload),
            background: note.background,
            titleStyle: note.titleStyle
        )
        TimelineStore.shared.update(updated)
    }

    /// Phase F.1.0 — closure passed to text cards' `onTap:` parameter.
    /// Looks up the tapped note by id and arms the editor sheet for
    /// edit mode. Filters to `.text` content only — `.stat` / `.list` /
    /// `.quote` aren't authored by the current editor and `.media` will
    /// open `MediaViewerScreen` separately when wired (today, media-card
    /// taps still go through `NoteCard`'s internal viewer presenter).
    private func requestEdit(_ noteId: UUID) {
        guard let note = TimelineStore.shared.notes.first(where: { $0.id == noteId }) else { return }
        if case .text = note.content {
            editingNote = note
        }
    }

    /// Convenience: only fire `requestEdit` for text-shaped notes. Cards
    /// with non-text content (stat/list/quote/media) get `nil` here so
    /// `onTapGesture` on their text scaffold no-ops. Media cards retain
    /// their internal media-viewer tap.
    private func tapHandler(for note: MockNote) -> (() -> Void)? {
        guard case .text = note.content else { return nil }
        return { requestEdit(note.id) }
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

                    // Inline banner-style discoverability tip. `TipView`
                    // (vs `.popoverTip`) avoids the popover-placement
                    // squeeze — there's no good spot for a floating
                    // arrow here: above the toggle clips into the safe
                    // area, below it covers the first card. As an
                    // inline row the tip takes its own dedicated slice
                    // of the layout and auto-disappears when its rules
                    // invalidate (after the user pins/deletes once).
                    TipView(cardActionsTip)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

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
            // Phase F.0.3 — thin animated indeterminate progress bar at
            // the very top of the timeline while the day fetch is in
            // flight. Replaces the prior redacted-skeleton approach,
            // which flashed in/out on every short day-switch and felt
            // noisy. The bar transitions opacity smoothly and doesn't
            // reorganize the layout when it appears or disappears.
            .overlay(alignment: .top) {
                if isLoadingNotes {
                    LoadingBar()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: isLoadingNotes)
            .animation(.easeOut(duration: 0.18), value: viewMode)
            .animation(.easeOut(duration: 0.18), value: boardLayout)
            // Phase F.0.3 — horizontal swipe between days. `simultaneous`
            // so vertical scroll keeps working; the strict horizontal-
            // dominance guard (1.5× the vertical translation, plus a
            // 60pt minimum) ensures only intentional swipes register.
            .simultaneousGesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .local)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > abs(dy) * 1.5, abs(dx) > 60 else { return }
                        TimelineStore.shared.shiftSelectedDate(byDays: dx > 0 ? -1 : 1)
                    }
            )
        }
        // Phase F.1.1b'.zoom — viewer overlay lives at `RootView` so
        // its z-order is above the TabBar. Cards pull the tap handler
        // from `EnvironmentValues.mediaTapHandler` (injected by
        // RootView).
        .overlay(alignment: .bottomTrailing) {
            // Menu attached directly to the FAB — popup anchors to the
            // button itself rather than sliding up from the screen
            // bottom (the prior `.confirmationDialog` placement felt
            // disconnected from a bottom-right FAB). On iOS 26 the Menu
            // gets the standard glass-styled popover.
            //
            // FAB stays persistent; the ScrollView's `.contentMargins`
            // reserves a 120pt bottom buffer so the last card never
            // ends up underneath the button. The viewer overlay (at
            // RootView level) z-covers the FAB while presented — no
            // explicit hide-on-present plumbing needed.
            // SwiftUI's `Menu` anchored to a bottom-trailing FAB opens
            // upward and orders items closest-to-anchor first (so the
            // last-declared item renders at the visual TOP of the
            // popup). Text Note is the more frequent action — putting
            // it last in source places it on top, matching Apple Mail's
            // compose menu ordering.
            Menu {
                // Source order is bottom-to-top in the popup (SwiftUI
                // anchors the menu above the FAB and renders
                // last-declared closest to the visual top — closest to
                // the anchor for thumb travel). Frequency-first:
                // camera at the bottom of source = bottom of popup;
                // Text Note at top of popup = primary action.
                Button {
                    isCameraPresented = true
                } label: {
                    Label("Camera", systemImage: "camera")
                }
                Button {
                    isMediaPickerPresented = true
                } label: {
                    Label("Gallery", systemImage: "photo.on.rectangle")
                }
                Button {
                    isEditorPresented = true
                } label: {
                    Label("Note", systemImage: "note.text")
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
            preferredItemEncoding: .current,
            photoLibrary: .shared()
        )
        .onChange(of: mediaPickerItem) { _, newItem in
            // PhotosPicker dismisses on selection — wrap the picked
            // item in `InitialMedia.pickerItem` and open the editor
            // sheet so the user can add a caption + type before saving.
            if let newItem {
                pendingCapture = .pickerItem(newItem)
                isMediaEditorPresented = true
            }
        }
        // Phase F.1.1b'.camera — full-screen `UIImagePickerController`
        // for direct camera capture. On capture, route to the same
        // editor sheet as the picker path; on cancel, just dismiss.
        //
        // Phase F.1.2.cameraflow — present the editor sheet from
        // `onDismiss` (after the cover has fully dismissed) rather than
        // from inside `onPick` (mid-dismissal). UIKit doesn't allow
        // simultaneous present + dismiss on the same view controller;
        // setting both `isCameraPresented = false` and
        // `isMediaEditorPresented = true` in the same closure caused
        // the very first capture to silently fail to open the editor.
        .fullScreenCover(
            isPresented: $isCameraPresented,
            onDismiss: {
                if presentEditorAfterCameraDismiss {
                    presentEditorAfterCameraDismiss = false
                    isMediaEditorPresented = true
                }
            }
        ) {
            CameraPicker { capture in
                isCameraPresented = false
                guard let capture else { return }
                switch capture {
                case .image(let image):
                    pendingCapture = .cameraImage(image)
                case .video(let url):
                    pendingCapture = .cameraVideoURL(url)
                }
                presentEditorAfterCameraDismiss = true
            }
            .ignoresSafeArea()
        }
        .sheet(
            isPresented: $isEditorPresented
        ) {
            NoteEditorScreen()
        }
        // Phase F.1.0 — edit-mode editor, presented when the user taps a
        // text card. Uses `.sheet(item:)` so the binding clears when the
        // user dismisses, which is also our autosave trigger via
        // `NoteEditorScreen.onDisappear`.
        .sheet(item: $editingNote) { note in
            NoteEditorScreen(editing: note)
        }
        .sheet(
            isPresented: $isMediaEditorPresented,
            onDismiss: {
                mediaPickerItem = nil
                pendingCapture = nil
            }
        ) {
            MediaNoteEditorScreen(initialMedia: pendingCapture)
        }
        // Phase F.1.2.caption — long-press → "Edit caption" sheet for
        // media notes. Light-weight: just a multi-line caption field +
        // Cancel/Save. Reconstructs the MockNote with the updated
        // payload and routes through `TimelineStore.update` (which
        // handles the optimistic in-memory swap + background persist).
        .sheet(isPresented: editingCaptionPresented) {
            if let id = editingCaptionNoteId,
               let note = TimelineStore.shared.notes.first(where: { $0.id == id }) {
                CaptionEditSheet(
                    initialCaption: note.mediaPayload?.caption,
                    onSave: { newCaption in
                        saveCaption(noteId: id, newCaption: newCaption)
                    }
                )
            }
        }
        // Phase F.0.3 — graphical date picker for "jump to any date."
        // Tapping the header date column opens this. `.medium` detent
        // keeps the calendar comfortably sized without taking the whole
        // screen.
        .sheet(isPresented: $isDatePickerPresented) {
            DatePickerSheet(
                selection: TimelineStore.shared.selectedDate,
                onSelect: { picked in
                    TimelineStore.shared.selectDate(picked)
                    isDatePickerPresented = false
                },
                onDismiss: { isDatePickerPresented = false }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
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

    /// Phase F.0.3 — date navigator header. Layered affordances:
    /// 1. Chevron buttons flanking the date title = previous / next day.
    /// 2. Tap the date title = open a graphical `DatePicker` sheet.
    /// 3. "Today" pill below the row when not on today = jump back.
    /// 4. Swipe gesture on the content area (wired separately) = prev/next.
    ///
    /// Layout: a small `TODAY` / weekday caption sits in its own top row
    /// alongside the right-side controls (Board sub-mode + gear). The
    /// chevrons flank only the big serif date title in the row below, so
    /// the 44pt-tall chevron tap targets center cleanly against the 28pt
    /// title (rather than floating mid-column when the caption was
    /// stacked above the title inside the same chevron HStack).
    private var header: some View {
        // Spacing 0 + a 40pt chevron tap target (down from 44pt) tightens
        // the caption-to-title gap to ~6pt — close to the 4pt the prior
        // single-VStack-button layout had, while keeping a comfortable
        // tap area for previous/next-day navigation.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(dayOfWeek)
                    .font(.DS.sans(size: 11, weight: .bold))
                    .tracking(0.88)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.DS.fg2)
                Spacer(minLength: 8)
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

            HStack(alignment: .center, spacing: 4) {
                chevronButton(.left)

                Button {
                    isDatePickerPresented = true
                } label: {
                    Text(dateTitle)
                        .font(.DS.serif(size: 28, weight: .bold))
                        .tracking(-0.56)  // -0.02em at 28pt
                        .foregroundStyle(Color.DS.ink)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pick a date")

                chevronButton(.right)

                Spacer(minLength: 8)

                // Phase F.1.2.weekstrip — Today pill moved inline next
                // to the chevrons so it doesn't add a dedicated row of
                // vertical space when the user is on a non-today date.
                // The chevron row's 40pt height comfortably hosts the
                // ~30pt pill on the trailing edge.
                if !TimelineStore.shared.isViewingToday {
                    todayPill
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }

            // Phase F.1.2.weekstrip — minimal motivational indicator.
            // Sits between the date row and the view toggle so the user
            // sees their week-at-a-glance every time they open Today.
            weekStrip
                .padding(.top, 6)
        }
        .animation(.easeOut(duration: 0.18), value: TimelineStore.shared.selectedDate)
    }

    /// Wraps `WeekStripView` with bindings to the live stores.
    /// `WeekStripStore.daysWithNotes` is read inside `body` so the
    /// Observation framework re-renders the strip when a note add /
    /// delete / week-change updates the set. Phase F.1.2.midnight —
    /// also reads `TimelineStore.currentDay` so the today indicator
    /// re-positions when midnight rolls over.
    private var weekStrip: some View {
        let selected = TimelineStore.shared.selectedDate
        let days = WeekStripView.days(forWeekContaining: selected)
        return WeekStripView(
            days: days,
            selectedDay: selected,
            currentDay: TimelineStore.shared.currentDay,
            filledDays: WeekStripStore.shared.daysWithNotes,
            onTap: { tapped in
                TimelineStore.shared.selectDate(tapped)
            }
        )
    }

    private enum ChevronDirection { case left, right }

    @ViewBuilder
    private func chevronButton(_ direction: ChevronDirection) -> some View {
        Button {
            TimelineStore.shared.shiftSelectedDate(byDays: direction == .left ? -1 : 1)
        } label: {
            Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.DS.fg2)
                .frame(width: 32, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction == .left ? "Previous day" : "Next day")
    }

    /// "Today" pill — reset-to-today affordance shown only when viewing a
    /// non-today date. Compact, sage-tinted, hugs the leading edge.
    private var todayPill: some View {
        Button {
            TimelineStore.shared.goToToday()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                Text("Today")
                    .font(.DS.sans(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.DS.sageDeep)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.DS.sageSoft)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to today")
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
        let date = TimelineStore.shared.selectedDate
        let weekday = date.formatted(.dateTime.weekday(.wide))
        // Phase F.1.2.midnight — relative-day labels compare against the
        // observed `currentDay` rather than calling
        // `Calendar.current.isDateInToday(_:)` etc. The latter reads
        // `Date()` each invocation but isn't observed, so the label
        // wouldn't update at midnight. Reading `currentDay` here
        // registers TimelineScreen as an observer; midnight rollover
        // crossfades the label via the `withAnimation` in the store.
        let today = TimelineStore.shared.currentDay
        let cal = Calendar.current
        if date == today { return "Today · \(weekday)" }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: today),
           date == yesterday { return "Yesterday · \(weekday)" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: today),
           date == tomorrow { return "Tomorrow · \(weekday)" }
        return weekday
    }

    private var dateTitle: String {
        TimelineStore.shared.selectedDate.formatted(.dateTime.month(.wide).day())
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
        // Empty state shows when there are zero notes — same UI whether
        // we're still loading (in which case `LoadingBar` overlays it
        // from the top) or actually empty for the day. Less jarring
        // than swapping the layout in/out around the brief load.
        if notes.isEmpty {
            emptyState
        } else {
            switch viewMode {
            case .timeline:
                timelineContent
            case .board:
                boardContent
            }
        }
    }

    /// Timeline view + Pinned section above it.
    ///
    /// Unlike Board (where pinned notes are *removed* from the sub-mode
    /// content below to avoid duplicates), Timeline deliberately shows
    /// pinned notes in **both** places: surfaced at the top for quick
    /// access, AND retained in their natural chronological slot in the
    /// rail. The chronological rail is the timeline's whole point —
    /// ripping a note out of its time slot would distort the day's
    /// shape — so the Pinned section here is a lightweight quick-access
    /// shelf, not a re-categorization.
    @ViewBuilder
    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !pinnedNotes.isEmpty {
                pinnedSection
            }
            timelineView
        }
    }

    /// Dispatches Board rendering based on `boardLayout`. The Pinned
    /// section sits at the top when any note is pinned; the sub-mode-
    /// specific layout below it sees only the unpinned subset, so a
    /// pinned note appears exactly once on Board (unlike Timeline,
    /// where it deliberately appears in both the shelf and the rail).
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
                    onRequestDelete: { requestDelete($0) },
                    onRequestEdit: { requestEdit($0) },
                    mediaTapHandler: mediaTapHandler,
                    onRequestEditCaption: { requestEditCaption($0) }
                )
            }
        }
    }

    /// The "Pinned" section rendered at the top of every view (Phase
    /// E.5.15 introduced it on Board; later expanded to Timeline so the
    /// affordance is consistent across the whole Today screen).
    ///
    /// **Layout-per-mode.** For Timeline / Cards / Stack the pinned
    /// cards render in a 2-col masonry — pinned notes are the user's
    /// "important now" list, and a flat masonry surfaces them clearly
    /// without the per-type stacking abstraction (you want pinned items
    /// immediately readable, not collapsed into a pile). For Group the
    /// pinned cards render in a horizontal scroll rail to match Group's
    /// all-rails visual rhythm.
    ///
    /// **Duplication semantics differ by mode.** Board sub-modes
    /// (Cards / Stack / Group) feed `unpinnedNotes` into their content
    /// below the section, so a pinned note appears *once* — in the
    /// shelf only. Timeline feeds the full chronological list into the
    /// rail below, so a pinned note appears *twice* — in the shelf AND
    /// in its natural time slot. Pulling pinned items out of the rail
    /// would distort the day's chronological shape, which is the
    /// timeline's whole point.
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

            // Rail variant only on Board / Group — Timeline always uses
            // masonry. Without the `viewMode == .board` guard, switching
            // from Board+Group to Timeline would leak the rail layout
            // onto the Timeline pinned shelf because `boardLayout` state
            // persists across mode toggles.
            if viewMode == .board && boardLayout == .grouped {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(pinnedNotes) { note in
                            KeepCard(
                                note: note,
                                onRequestDelete: { requestDelete($0.id) },
                                onTap: tapHandler(for: note),
                                mediaTapHandler: mediaTapHandler,
                                onRequestEditCaption: { requestEditCaption($0.id) }
                            )
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
                    KeepCard(
                                note: note,
                                onRequestDelete: { requestDelete($0.id) },
                                onTap: tapHandler(for: note),
                                onRequestEditCaption: { requestEditCaption($0.id) }
                            )
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
            onRequestDelete: requestDelete,
            onRequestEdit: requestEdit,
            mediaTapHandler: mediaTapHandler,
            onRequestEditCaption: requestEditCaption
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
                                KeepCard(
                                note: note,
                                onRequestDelete: { requestDelete($0.id) },
                                onTap: tapHandler(for: note),
                                mediaTapHandler: mediaTapHandler,
                                onRequestEditCaption: { requestEditCaption($0.id) }
                            )
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
                        onRequestDelete: requestDelete,
                        onTap: tapHandler(for: note),
                        mediaTapHandler: mediaTapHandler,
                        onRequestEditCaption: requestEditCaption
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
