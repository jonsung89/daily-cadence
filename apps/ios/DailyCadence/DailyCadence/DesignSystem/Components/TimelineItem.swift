import SwiftUI

/// A row on the daily timeline: right-aligned time column, a vertical rail
/// with a colored dot, and a generic trailing slot (typically a `NoteCard`).
///
/// Matches the geometry in `mobile.css`:
/// - Time column ~40pt wide, mono 10pt, `fg-2`, top-aligned ~18pt from top
/// - Rail: 1pt `border-1` vertical line running the full row height
/// - Dot: 12pt circle in the type's pigment, positioned ~20pt from the top,
///   with a 4pt `bg-1` ring that visually "breaks" the line at the dot
///
/// Stack multiple `TimelineItem`s in a `VStack(spacing: 0)` and the rails
/// connect into a single continuous vertical line. Use `lineStyle` to hide
/// the line above the first item or below the last item — the timeline
/// should appear to start at the first dot and end at the last.

/// How much of the vertical rail to draw on a `TimelineItem`.
///
/// Defined at the top level (rather than nested inside `TimelineItem`) so
/// callers can reference it without having to restate the generic type
/// parameter — e.g., `TimelineLineStyle.belowDotOnly` reads cleanly vs.
/// `TimelineItem<NoteCard>.LineStyle.belowDotOnly`.
enum TimelineLineStyle {
    /// Line runs full height (use for middle items).
    case full
    /// Line only below the dot (use for the first item in a timeline).
    case belowDotOnly
    /// Line only above the dot (use for the last item).
    case aboveDotOnly
    /// No rail line, just the dot (use for a single-item timeline).
    case dotOnly
}

struct TimelineItem<Trailing: View>: View {
    let time: String
    let type: NoteType
    let lineStyle: TimelineLineStyle
    @ViewBuilder let trailing: () -> Trailing

    init(
        time: String,
        type: NoteType,
        lineStyle: TimelineLineStyle = .full,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.time = time
        self.type = type
        self.lineStyle = lineStyle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Time column
            Text(time)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.DS.fg2)
                // 56pt fits the longest 8-character time ("12:59 PM" /
                // "10:38 AM") at 10pt monospaced with breathing room.
                // Prior 44pt was sized for 7-char times ("9:02 AM") and
                // wrapped 10-something AM/PM times to two lines.
                .lineLimit(1)
                .frame(width: 56, alignment: .trailing)
                .padding(.top, 18)

            // Rail column — line + dot centered in a 20pt-wide lane
            ZStack(alignment: .top) {
                // Vertical rail line — drawn first so the dot can cover it
                railLine
                // Dot with cream ring so the line appears "broken" at the dot
                ZStack {
                    Circle()
                        .fill(Color.DS.bg1)
                        .frame(width: 20, height: 20)
                    Circle()
                        .fill(type.color)
                        .frame(width: 12, height: 12)
                }
                .padding(.top, 14)
            }
            .frame(width: 20)

            // Trailing slot — typically a NoteCard
            trailing()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var railLine: some View {
        switch lineStyle {
        case .full:
            Rectangle()
                .fill(Color.DS.border1)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        case .belowDotOnly:
            VStack(spacing: 0) {
                Spacer().frame(height: 24)  // 14pt top padding + 10pt half-dot
                Rectangle()
                    .fill(Color.DS.border1)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
        case .aboveDotOnly:
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.DS.border1)
                    .frame(width: 1, height: 24)
                Spacer()
            }
        case .dotOnly:
            EmptyView()
        }
    }
}

#Preview("Three items, light") {
    VStack(spacing: 0) {
        TimelineItem(time: "7:32 AM", type: .workout, lineStyle: .belowDotOnly) {
            NoteCard(
                type: .workout,
                title: "Leg day — felt strong",
                message: "PR attempt on squats today. 225 × 6."
            )
        }
        TimelineItem(time: "12:15 PM", type: .meal, lineStyle: .full) {
            NoteCard(
                type: .meal,
                title: "Sushi bowl with coworkers"
            )
        }
        TimelineItem(time: "6:20 PM", type: .activity, lineStyle: .full) {
            NoteCard(
                type: .activity,
                title: "4.2 mile walk",
                message: "Looped around the neighborhood at dusk."
            )
        }
        TimelineItem(time: "11:02 PM", type: .sleep, lineStyle: .aboveDotOnly) {
            NoteCard(
                type: .sleep,
                title: "Lights out",
                message: "Planning 7h."
            )
        }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 20)
    .background(Color.DS.bg1)
}

#Preview("Three items, dark") {
    VStack(spacing: 0) {
        TimelineItem(time: "7:32 AM", type: .workout, lineStyle: .belowDotOnly) {
            NoteCard(
                type: .workout,
                title: "Leg day — felt strong",
                message: "PR attempt on squats today. 225 × 6."
            )
        }
        TimelineItem(time: "12:15 PM", type: .meal, lineStyle: .full) {
            NoteCard(
                type: .meal,
                title: "Sushi bowl with coworkers"
            )
        }
        TimelineItem(time: "11:02 PM", type: .sleep, lineStyle: .aboveDotOnly) {
            NoteCard(
                type: .sleep,
                title: "Lights out",
                message: "Planning 7h."
            )
        }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 20)
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}
