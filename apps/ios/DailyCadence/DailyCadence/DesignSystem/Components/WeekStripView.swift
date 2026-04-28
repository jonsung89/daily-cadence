import SwiftUI

/// Phase F.1.2.weekstrip — minimal motivational indicator above the
/// Today screen's view toggle. Renders the current week as 7 columns
/// (S M T W T F S, locale-aware first day) with a small dot per
/// column showing whether that day has any notes. Today gets a
/// stronger background tint; the user's selected day (when not today)
/// gets a subtle ring; tapping any column navigates the timeline to
/// that day.
///
/// Sized small (~36pt tall) so it slots in between the date header
/// and the Timeline / Board toggle without competing for attention.
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
    /// Days with at least one note. Match-by-startOfDay equality.
    let filledDays: Set<Date>
    /// Tap handler — caller routes to `TimelineStore.selectDate(...)`.
    let onTap: (Date) -> Void

    private let cal = Calendar.current
    /// Locale-aware single-character day labels (e.g. ["S","M","T","W","T","F","S"]
    /// in en_US). Cached once per render — `veryShortWeekdaySymbols`
    /// is a Foundation lookup, not free in tight loops.
    private var weekdaySymbols: [String] { cal.veryShortWeekdaySymbols }

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
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let hasNotes = filledDays.contains(cal.startOfDay(for: day))
        let weekdayIndex = cal.component(.weekday, from: day) - 1 // 1...7 → 0...6
        let letter = weekdaySymbols.indices.contains(weekdayIndex)
            ? weekdaySymbols[weekdayIndex]
            : ""

        VStack(spacing: 6) {
            Text(letter)
                .font(.DS.sans(size: 11, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.DS.ink : Color.DS.fg2)

            // Dot states:
            // - has notes: filled with the user's primary theme color (sage by default)
            // - no notes: hollow ring in fg2 @ 0.4 opacity
            ZStack {
                if hasNotes {
                    Circle()
                        .fill(Color.DS.sage)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .strokeBorder(Color.DS.fg2.opacity(0.4), lineWidth: 1)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 8, height: 8)
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
        .overlay(
            // Today gets a 1pt sage-tinted ring on TOP of the selected
            // fill — makes "today" identifiable even when the user is
            // viewing a different day (no fill on this column).
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isToday ? Color.DS.sage.opacity(0.5) : Color.clear,
                    lineWidth: 1
                )
                .padding(.horizontal, 3)
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
    let today = Date()
    let days = WeekStripView.days(forWeekContaining: today)
    let cal = Calendar.current
    return WeekStripView(
        days: days,
        selectedDay: today,
        filledDays: Set([
            cal.startOfDay(for: today),
            cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: today))!,
            cal.date(byAdding: .day, value: -3, to: cal.startOfDay(for: today))!,
        ]),
        onTap: { _ in }
    )
    .background(Color.DS.bg1)
}

#Preview("Today's week, dark") {
    let today = Date()
    let days = WeekStripView.days(forWeekContaining: today)
    return WeekStripView(
        days: days,
        selectedDay: cal.date(byAdding: .day, value: -2, to: today)!,
        filledDays: Set([cal.startOfDay(for: today)]),
        onTap: { _ in }
    )
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}

private let cal = Calendar.current
