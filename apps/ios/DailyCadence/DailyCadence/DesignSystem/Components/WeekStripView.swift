import SwiftUI

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

    private let cal = Calendar.current
    /// Locale-aware single-character day labels (e.g. ["S","M","T","W","T","F","S"]
    /// in en_US). Cached once per render — `veryShortWeekdaySymbols`
    /// is a Foundation lookup, not free in tight loops.
    private var weekdaySymbols: [String] { cal.veryShortWeekdaySymbols }

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
                column(for: day)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(day) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        .accessibilityLabel(accessibilityLabel(day: day, isToday: isToday, isSelected: isSelected, hasNotes: hasNotes))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityLabel(day: Date, isToday: Bool, isSelected: Bool, hasNotes: Bool) -> String {
        let weekday = day.formatted(.dateTime.weekday(.wide))
        var label = weekday
        if isToday { label += ", today" }
        if isSelected && !isToday { label += ", selected" }
        label += hasNotes ? ". Has notes." : ". No notes."
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
