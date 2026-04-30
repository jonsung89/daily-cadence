import SwiftUI
import UIKit

/// Phase F.1.2.weekstrip — motivational indicator above the Today
/// screen's view toggle. Renders the user's week as a paged dial:
/// the day-of-week letters (S M T W T F S, locale-aware first day)
/// stay fixed at the top while the date numbers slide horizontally
/// in response to swipes — same visual + interaction model as Apple
/// Calendar's week strip. Tapping any column navigates the timeline
/// to that day; long-pressing opens the emoji picker (`EmojiPickerSheet`)
/// to mark the day.
///
/// **Paged via `TabView`.** Each "page" is one week of date numbers.
/// `TabView`'s page style gives the interactive drag, peek-of-adjacent-
/// weeks during the swipe, snap-on-release physics, and velocity-based
/// commit — all native, no custom gesture math. Static letter row
/// sits above the TabView so it never moves with the date row.
///
/// **Selection sync.** The TabView's selection (`visibleWeekStart`) is
/// the start of the currently-displayed week. When the user pages,
/// `selectedDay` shifts by the matching day delta to preserve the
/// weekday (Apple Calendar pattern: viewing Wed → swipe → Wed of new
/// week). When `selectedDay` changes externally (chevron tap, day
/// picker, etc.), `visibleWeekStart` snaps to that week so the dial
/// stays in sync.
///
/// Reads `WeekStripStore.shared.daysWithNotes`, `TimelineStore.shared.selectedDate`,
/// `DayMarkStore.shared.marks` upstream — Observation wires re-renders.
struct WeekStripView: View {
    /// The currently-selected day. Drives both the "selected" highlight
    /// AND the dial's visible-week sync. `Calendar.current.startOfDay(for:)`-
    /// normalized.
    let selectedDay: Date
    /// Phase F.1.2.midnight — observed source of "what is today."
    /// Passed in (rather than reading `Calendar.current.isDateInToday`
    /// inside `body`) so the strip re-renders when midnight rolls
    /// over. Caller reads `TimelineStore.shared.currentDay` and forwards
    /// here. `Calendar.current.startOfDay(for:)`-normalized.
    let currentDay: Date
    /// Days with at least one note. Match-by-startOfDay equality.
    let filledDays: Set<Date>
    /// Tap handler — caller routes to `TimelineStore.selectDate(...)`.
    /// Also fired internally when the user pages between weeks (we
    /// shift the selection by the day delta, then call this so the
    /// upstream store updates).
    let onTap: (Date) -> Void
    /// Phase F.1.2.daymarks — emoji-by-day map, keyed by `startOfDay`.
    /// Defaults empty so existing callers (previews, tests) don't need
    /// to thread it through. Caller passes `DayMarkStore.shared.marks`
    /// in production wiring; mutations route directly through
    /// `DayMarkStore.shared.set/clear` from inside the picker.
    var dayMarks: [Date: String] = [:]

    /// Phase F.1.2.weekstrip.dial — the start-of-week (Sunday in en_US,
    /// locale-aware elsewhere) of the currently-displayed page.
    /// `TabView` selection binds to this; mutations come from either
    /// the user paging the TabView or external `selectedDay` changes
    /// landing the strip on a different week.
    @State private var visibleWeekStart: Date

    /// Phase F.1.2.daymarks — id of the day whose `EmojiPickerSheet`
    /// is open. Internal state because the picker is purely week-strip
    /// UX; parents only inject `dayMarks` for display.
    @State private var pickerDay: Date? = nil

    /// Phase F.1.2.daymarks — id of the day currently being held down
    /// for a potential long-press. Drives the scale-down feedback so
    /// the user feels the press registering before the picker opens.
    @State private var pressingDay: Date? = nil

    private let cal = Calendar.current
    /// Locale-aware single-character day labels (e.g. ["S","M","T","W","T","F","S"]
    /// in en_US). Cached once per render — `veryShortWeekdaySymbols`
    /// is a Foundation lookup, not free in tight loops.
    private var weekdaySymbols: [String] { cal.veryShortWeekdaySymbols }

    /// Day-mark feature constants for the shared `EmojiPickerSheet`.
    /// Curated quick-picks tuned for "mark a special day" intents
    /// (birthday / anniversary / milestone / alert). The recent-
    /// storage key is per-feature so future emoji-picker callers
    /// (reactions, mood tagging) get their own history.
    private static let dayMarkCommonlyUsed: [String] = [
        "🎂", "🎉", "❤️", "💍", "⭐",
        "✨", "🎁", "🎈", "🍾", "🥂",
        "👶", "🎓", "🌈", "✈️", "🏠",
        "❗", "📅", "🏆", "💐", "🌙",
    ]
    private static let dayMarkRecentStorageKey = "com.jonsung.DailyCadence.daymarks.recentEmojis"

    /// Phase F.1.2.midnight — namespace for the today-ring matched-geo.
    /// Within a single page, the sage ring slides between adjacent
    /// columns at midnight rollover (Mon → Tue inside the same week).
    /// Cross-page rollovers (Sat → Sun across the Sunday week
    /// boundary) fade the ring out instead — `matchedGeometryEffect`
    /// doesn't bridge separate `TabView` pages.
    @Namespace private var todayRingNamespace

    /// Range of paged weeks: ±52 weeks from this view's mount-time
    /// "current week." 105 total — covers a full year of paging in
    /// either direction. `TabView` is lazy so off-screen pages don't
    /// pay layout / observation costs.
    private static let weekOffsets = Array(-52...52)
    /// Anchor week for the dial range. Captured once at init so the
    /// available `weekStartDates` stay stable across renders.
    private let baseWeekStart: Date

    init(
        selectedDay: Date,
        currentDay: Date,
        filledDays: Set<Date>,
        onTap: @escaping (Date) -> Void,
        dayMarks: [Date: String] = [:]
    ) {
        self.selectedDay = selectedDay
        self.currentDay = currentDay
        self.filledDays = filledDays
        self.onTap = onTap
        self.dayMarks = dayMarks
        let cal = Calendar.current
        let initialWeek = Self.startOfWeek(for: selectedDay, calendar: cal)
        self._visibleWeekStart = State(initialValue: initialWeek)
        self.baseWeekStart = Self.startOfWeek(for: .now, calendar: cal)
    }

    var body: some View {
        VStack(spacing: 4) {
            weekdayLetterRow
                .padding(.horizontal, 12)

            TabView(selection: $visibleWeekStart) {
                ForEach(weekStartDates, id: \.self) { weekStart in
                    weekDateRow(weekStart: weekStart)
                        .padding(.horizontal, 12)
                        .tag(weekStart)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Fixed height so the TabView doesn't expand vertically.
            // Sized for 13pt number + 9pt dot + spacing + per-cell
            // vertical padding (8pt × 2) + hit-area pad (4pt × 2).
            .frame(height: 60)
        }
        .padding(.vertical, 4)
        .onChange(of: visibleWeekStart) { oldValue, newValue in
            // User paged the dial. Shift `selectedDay` by the same
            // day delta so the weekday is preserved (Wed → Wed in the
            // new week — Apple Calendar pattern). The upstream
            // `onTap` callback updates `TimelineStore.selectedDate`,
            // which then re-flows back as the new `selectedDay` prop
            // — but `visibleWeekStart` already equals the new week,
            // so the `.onChange(of: selectedDay)` handler short-
            // circuits without re-animating.
            guard oldValue != newValue else { return }
            let dayDelta = cal.dateComponents([.day], from: oldValue, to: newValue).day ?? 0
            guard dayDelta != 0 else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            let newSelected = cal.date(byAdding: .day, value: dayDelta, to: selectedDay) ?? selectedDay
            onTap(newSelected)
        }
        .onChange(of: selectedDay) { _, newValue in
            // External `selectedDay` change (chevron tap, date picker,
            // etc.). If it lands in a different week than the dial is
            // showing, animate the dial to that week. Same-week tap
            // is a no-op for the dial (just the highlight moves).
            let newWeekStart = Self.startOfWeek(for: newValue, calendar: cal)
            guard newWeekStart != visibleWeekStart else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                visibleWeekStart = newWeekStart
            }
        }
    }

    // MARK: - Static letter row

    private var weekdayLetterRow: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { idx in
                Text(weekdaySymbols.indices.contains(idx) ? weekdaySymbols[idx] : "")
                    .font(.DS.sans(size: 10, weight: .regular))
                    .foregroundStyle(Color.DS.fg2)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Paged date rows

    private var weekStartDates: [Date] {
        Self.weekOffsets.compactMap { offset in
            cal.date(byAdding: .day, value: offset * 7, to: baseWeekStart)
        }
    }

    private func daysInWeek(starting weekStart: Date) -> [Date] {
        (0..<7).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: weekStart)
        }
    }

    private func weekDateRow(weekStart: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(daysInWeek(starting: weekStart), id: \.self) { day in
                let normalized = cal.startOfDay(for: day)
                dateCell(for: day)
                    // Phase F.1.2.daymarks — visual feedback during a
                    // long-press hold. Scales the cell to 0.94×
                    // (matches iOS's context-menu lift feel) so the
                    // user knows the press is registering before the
                    // picker pops at 0.35s. Spring back when released
                    // or when the sheet takes over.
                    .scaleEffect(pressingDay == normalized ? 0.94 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressingDay)
                    .frame(maxWidth: .infinity)
                    // Pad the hit area beyond the visual (4pt vertical,
                    // 2pt horizontal) before stamping the contentShape
                    // so a slightly-off finger still registers. Doesn't
                    // shift the visual layout — `dateCell` already owns
                    // its visible padding inside its body.
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(day) }
                    // Phase F.1.2.daymarks — long-press opens the emoji
                    // picker. 0.35s is slightly snappier than iOS's
                    // 0.4s context-menu default, paired with the
                    // scale-down + medium haptic so the gesture feels
                    // instant. `maximumDistance: 50` (vs SwiftUI's 10pt
                    // default) tolerates the finger jitter that's
                    // normal during a 0.35s hold — without this the
                    // gesture silently cancels mid-press and the user
                    // has to retry.
                    .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 50) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        pickerDay = normalized
                        pressingDay = nil
                    } onPressingChanged: { isPressing in
                        // Soft haptic on touch-down — the missing
                        // "I felt that" feedback that iOS context
                        // menus give. Pairs with the medium haptic
                        // on long-press completion.
                        if isPressing, pressingDay != normalized {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                        pressingDay = isPressing ? normalized : nil
                    }
                    .sheet(isPresented: pickerPresentedBinding(for: day)) {
                        EmojiPickerSheet(
                            subtitle: "Mark this day",
                            title: normalized.formatted(.dateTime.weekday(.wide).month().day()),
                            commonlyUsed: Self.dayMarkCommonlyUsed,
                            recentStorageKey: Self.dayMarkRecentStorageKey,
                            currentSelection: dayMarks[normalized],
                            onSelect: { emoji in
                                DayMarkStore.shared.set(day: day, emoji: emoji)
                                pickerDay = nil
                            },
                            onRemove: dayMarks[normalized] != nil ? {
                                DayMarkStore.shared.clear(day: day)
                                pickerDay = nil
                            } : nil
                        )
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    }
            }
        }
    }

    @ViewBuilder
    private func dateCell(for day: Date) -> some View {
        let isToday = cal.isDate(day, inSameDayAs: currentDay)
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let hasNotes = filledDays.contains(cal.startOfDay(for: day))

        VStack(spacing: 4) {
            // Day-of-month number. Today bolds + uses ink; other days
            // stay regular + fg2 so today still reads first at a glance
            // even before the user notices the ring/pill chrome.
            Text(day.formatted(.dateTime.day()))
                .font(.DS.sans(size: 13, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? Color.DS.ink : Color.DS.fg2)
                .monospacedDigit()

            // Dot states:
            // - has notes: filled with the user's primary theme color (sage by default)
            // - no notes: hollow ring in fg2 @ 0.4 opacity
            ZStack {
                if hasNotes {
                    Circle()
                        .fill(Color.DS.sage)
                        .frame(width: 9, height: 9)
                } else {
                    Circle()
                        .strokeBorder(Color.DS.fg2.opacity(0.4), lineWidth: 1)
                        .frame(width: 9, height: 9)
                }
            }
            .frame(width: 11, height: 11)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            // Selected-day highlight: subtle sage soft fill that fills
            // the column's allocated width (with a 3pt inset so adjacent
            // selected pills wouldn't touch). Today AND selected = full
            // pill; selected (different day from today) also gets the
            // pill so the user sees which day they're navigating.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.DS.sageSoft : Color.clear)
                .padding(.horizontal, 3)
        )
        .overlay {
            // Today gets a 1pt sage-tinted ring on TOP of the selected
            // fill — makes "today" identifiable even when the user is
            // viewing a different day (no fill on this column).
            if isToday {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.DS.sage.opacity(0.5), lineWidth: 1)
                    .padding(.horizontal, 3)
                    .matchedGeometryEffect(id: "today-ring", in: todayRingNamespace)
            }
        }
        // Phase F.1.2.daymarks — emoji badge in the top-right corner
        // of each marked day's cell. Bumped 2pt up/right of the corner
        // so it reads as a stamp on top of the container rather than
        // crammed inside. `.transition` + `.animation` give a bouncy
        // scale-in on add and a fade-out on remove. `id: emoji` on the
        // Text forces SwiftUI to treat an emoji change as add+remove,
        // so swapping (e.g., 🎂 → ❗) animates rather than snaps.
        .overlay(alignment: .topTrailing) {
            if let emoji = dayMarks[cal.startOfDay(for: day)] {
                Text(emoji)
                    .font(.system(size: 14))
                    .id(emoji)
                    .padding(2)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    .offset(x: 2, y: -2)
                    .accessibilityLabel("Marked with \(emoji)")
            }
        }
        .animation(
            .bouncy(duration: 0.4, extraBounce: 0.2),
            value: dayMarks[cal.startOfDay(for: day)]
        )
        .accessibilityLabel(accessibilityLabel(day: day, isToday: isToday, isSelected: isSelected, hasNotes: hasNotes))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Helpers

    private func pickerPresentedBinding(for day: Date) -> Binding<Bool> {
        let normalized = cal.startOfDay(for: day)
        return Binding(
            get: { pickerDay == normalized },
            set: { newValue in
                if !newValue, pickerDay == normalized {
                    pickerDay = nil
                }
            }
        )
    }

    private func accessibilityLabel(day: Date, isToday: Bool, isSelected: Bool, hasNotes: Bool) -> String {
        let weekday = day.formatted(.dateTime.weekday(.wide))
        var label = weekday
        if isToday { label += ", today" }
        if isSelected && !isToday { label += ", selected" }
        label += hasNotes ? ". Has notes." : ". No notes."
        if let emoji = dayMarks[cal.startOfDay(for: day)] {
            label += " Marked with \(emoji)."
        }
        return label
    }

    /// Locale-aware "first day of the week containing `date`" — Sun
    /// in en_US, Mon elsewhere. Normalized to `startOfDay`.
    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        return calendar.startOfDay(for: interval?.start ?? date)
    }
}

// MARK: - Convenience builder

extension WeekStripView {
    /// Builds the seven-day array for the week containing `date`,
    /// normalized to `startOfDay` and ordered locale-first (Sun-first
    /// in en_US, Mon-first elsewhere). Kept as a public helper for
    /// any caller that wants the same week math the strip uses
    /// internally; the strip itself no longer requires callers to
    /// pre-compute this (see paged `TabView` body).
    static func days(forWeekContaining date: Date) -> [Date] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else { return [] }
        let start = cal.startOfDay(for: interval.start)
        return (0..<7).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: start)
        }
    }
}

#Preview("Today's week, light") {
    let today = Calendar.current.startOfDay(for: .now)
    let cal = Calendar.current
    return WeekStripView(
        selectedDay: today,
        currentDay: today,
        filledDays: Set([
            today,
            cal.date(byAdding: .day, value: -1, to: today)!,
            cal.date(byAdding: .day, value: -3, to: today)!,
        ]),
        onTap: { _ in }
    )
    .background(Color.DS.bg1)
}

#Preview("Today's week, dark") {
    let today = Calendar.current.startOfDay(for: .now)
    let cal = Calendar.current
    return WeekStripView(
        selectedDay: cal.date(byAdding: .day, value: -2, to: today)!,
        currentDay: today,
        filledDays: Set([today]),
        onTap: { _ in }
    )
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}
