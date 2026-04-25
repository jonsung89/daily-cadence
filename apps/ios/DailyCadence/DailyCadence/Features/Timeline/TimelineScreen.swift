import SwiftUI

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
    @State private var viewMode: TimelineViewMode = .timeline
    @State private var isEditorPresented = false

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
                        .padding(.bottom, 16)

                    content
                        .padding(.horizontal, horizontalPadding(for: viewMode))
                }
                .padding(.bottom, 100)  // breathing room so FAB doesn't cover the last item
            }
            .background(Color.DS.bg1)
            .toolbar(.hidden, for: .navigationBar)
        }
        .overlay(alignment: .bottomTrailing) {
            FAB { isEditorPresented = true }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
        }
        .sheet(isPresented: $isEditorPresented) {
            NoteEditorScreen()
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

    // MARK: - Segmented toggle

    private var segmentedToggle: some View {
        Segmented(
            options: TimelineViewMode.allCases.map { mode in
                SegmentedOption(id: mode, title: mode.title, systemImage: mode.systemImage)
            },
            selection: $viewMode
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
                KeepGrid(items: notes) { note in
                    KeepCard(note: note)
                }
            }
        }
    }

    private func horizontalPadding(for mode: TimelineViewMode) -> CGFloat {
        switch mode {
        case .timeline: return 8    // timeline items carry their own left gutter
        case .board:    return 16   // cards sit directly against the outer padding
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
                        messageStyle: note.messageStyle
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
