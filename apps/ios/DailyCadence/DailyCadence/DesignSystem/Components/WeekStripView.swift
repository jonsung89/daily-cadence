import SwiftUI
import UIKit

/// Phase F.1.2.weekstrip — motivational indicator above the Today
/// screen's view toggle. Renders the current week as 7 columns,
/// each showing weekday letter (S M T W T F S, locale-aware first
/// day), day-of-month number, and a dot indicating whether that day
/// has any notes. Today gets a stronger background tint; the user's
/// selected day (when not today) gets a subtle ring; tapping any
/// column navigates the timeline to that day.
///
/// Reads `WeekStripStore.shared.daysWithNotes` and
/// `TimelineStore.shared.selectedDate` — Observation wires re-renders
/// automatically on either change.
struct WeekStripView: View {
    /// The full set of seven days in the user's current week, sorted
    /// chronologically (locale-aware first day). Computed from
    /// `Calendar.current.dateInterval(of: .weekOfYear)` based on the
    /// timeline's selected date.
    let days: [Date]
    /// The currently-selected day (drives the "selected" highlight).
    /// `Calendar.current.startOfDay(for:)`-normalized.
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
    let onTap: (Date) -> Void
    /// Phase F.1.2.daymarks — emoji-by-day map, keyed by `startOfDay`.
    /// Defaults empty so existing callers (previews, tests) don't need
    /// to thread it through. Caller passes `DayMarkStore.shared.marks`
    /// in production wiring; mutations route directly through
    /// `DayMarkStore.shared.set/clear` from inside the picker (same
    /// singleton-mutation pattern the rest of the strip uses for
    /// `WeekStripStore`).
    var dayMarks: [Date: String] = [:]

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
    /// When midnight advances `currentDay` from one column to an adjacent
    /// column within the displayed week (e.g., Mon → Tue), SwiftUI slides
    /// the sage ring between cells instead of fading out + fading in.
    /// Cross-week rollovers (today moves outside the displayed days) just
    /// fade the ring out — no destination to slide to.
    @Namespace private var todayRingNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let normalized = cal.startOfDay(for: day)
                column(for: day)
                    // Phase F.1.2.daymarks — visual feedback during a
                    // long-press hold. Scales the cell to 0.94×
                    // (matches iOS's context-menu lift feel) so the
                    // user knows the press is registering before the
                    // picker pops at 0.35s. Spring back when released
                    // or when the popover takes over.
                    .scaleEffect(pressingDay == normalized ? 0.94 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressingDay)
                    .frame(maxWidth: .infinity)
                    // Pad the hit area beyond the visual (4pt vertical,
                    // 2pt horizontal) before stamping the contentShape
                    // so a slightly-off finger still registers. Doesn't
                    // shift the visual layout — `column` already owns
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
                    // has to retry. `onPressingChanged` drives the
                    // visual feedback during the hold; the perform
                    // closure fires the haptic + opens the popover.
                    .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 50) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        pickerDay = normalized
                        pressingDay = nil
                    } onPressingChanged: { isPressing in
                        // Light haptic on touch-down — the missing
                        // "I felt that" feedback that iOS context
                        // menus give. Pairs with the medium haptic
                        // on long-press completion to make the
                        // 0.35s threshold feel like the gesture is
                        // actively responding rather than waiting.
                        if isPressing, pressingDay != normalized {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                        pressingDay = isPressing ? normalized : nil
                    }
                    .sheet(isPresented: pickerPresentedBinding(for: day)) {
                        // Bottom sheet (vs. popover) — matches iOS-
                        // native reaction tray UX (Messenger, Discord,
                        // iMessage). Slide-up animation, drag indicator,
                        // dimmed backdrop, swipe-down to dismiss are
                        // all free with `.sheet`. Detents start at
                        // `.medium` (matches the reaction-tray feel)
                        // and let the user drag up to `.large` for the
                        // full catalog. `EmojiPickerSheet` is the
                        // reusable component — day-marks supplies its
                        // own quick-pick set + storage key for recents
                        // so future features (reactions, mood tags)
                        // can pass their own without polluting each
                        // other's history.
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
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        // Phase F.1.2.weekstrip — horizontal swipe between weeks.
        // Mirrors the timeline's day-swipe gesture (TimelineScreen
        // ~line 261): same `simultaneousGesture` + horizontal-
        // dominance guard so per-cell taps and long-presses still
        // arbitrate cleanly. Same-weekday selection in the new week
        // (Apple Calendar pattern): on Wed → swipe → Wed of new
        // week. Soft haptic on success matches iOS Calendar's feel.
        // Selection update flows through `TimelineStore.shiftSelectedDate(byDays:)`
        // which the upstream `weekStrip` accessor reads to recompute
        // the displayed days, so the strip re-renders automatically.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.5, abs(dx) > 60 else { return }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    TimelineStore.shared.shiftSelectedDate(byDays: dx > 0 ? -7 : 7)
                }
        )
    }

    /// One binding per day so each column's `.popover` modifier can
    /// fire independently without thrashing the others. Reads true
    /// when this column owns the open picker; setter resets when
    /// the popover dismisses (tap-outside, swipe-down).
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

    @ViewBuilder
    private func column(for day: Date) -> some View {
        let isToday = cal.isDate(day, inSameDayAs: currentDay)
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let hasNotes = filledDays.contains(cal.startOfDay(for: day))
        let weekdayIndex = cal.component(.weekday, from: day) - 1 // 1...7 → 0...6
        let letter = weekdaySymbols.indices.contains(weekdayIndex)
            ? weekdaySymbols[weekdayIndex]
            : ""

        VStack(spacing: 4) {
            Text(letter)
                .font(.DS.sans(size: 10, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.DS.ink : Color.DS.fg2)

            // Phase F.1.2.weekstrip.dates — day-of-month number, primary
            // info row of the strip. Today bolds + uses ink; other days
            // stay regular + fg2 so today still reads first at a glance
            // even before the user notices the ring/pill chrome.
            Text(day.formatted(.dateTime.day()))
                .font(.DS.sans(size: 13, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? Color.DS.ink : Color.DS.fg2)
                .monospacedDigit()

            // Dot states:
            // - has notes: filled with the user's primary theme color (sage by default)
            // - no notes: hollow ring in fg2 @ 0.4 opacity
            // Bumped 6→9pt this round so the dot holds its own next to
            // the letter + number rows rather than disappearing.
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
            // selected pills wouldn't touch). Earlier 4pt-padded version
            // read as a skinny tall oval; this one feels like a proper
            // bubble around the day. Today AND selected = full pill;
            // selected (different day from today) also gets the pill so
            // the user sees which day they're navigating.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.DS.sageSoft : Color.clear)
                .padding(.horizontal, 3)
        )
        .overlay {
            // Today gets a 1pt sage-tinted ring on TOP of the selected
            // fill — makes "today" identifiable even when the user is
            // viewing a different day (no fill on this column).
            // Phase F.1.2.midnight — `matchedGeometryEffect` so the ring
            // slides between adjacent columns at midnight rollover
            // within the displayed week (Mon → Tue, etc.). When the new
            // today is outside the displayed week (week-boundary
            // rollover), the ring fades out — no destination to slide
            // to. Only the today column attaches the modifier; non-today
            // columns render no ring at all.
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
}

// MARK: - Convenience builder

extension WeekStripView {
    /// Builds the seven-day array for the week containing `date`,
    /// normalized to `startOfDay` and ordered locale-first (Sun-first
    /// in en_US, Mon-first elsewhere).
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
    let days = WeekStripView.days(forWeekContaining: today)
    let cal = Calendar.current
    return WeekStripView(
        days: days,
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
    let days = WeekStripView.days(forWeekContaining: today)
    return WeekStripView(
        days: days,
        selectedDay: cal.date(byAdding: .day, value: -2, to: today)!,
        currentDay: today,
        filledDays: Set([today]),
        onTap: { _ in }
    )
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}

private let cal = Calendar.current
