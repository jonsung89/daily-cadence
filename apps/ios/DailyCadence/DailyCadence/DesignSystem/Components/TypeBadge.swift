import SwiftUI

/// The head row of a `NoteCard`: a small colored dot, an uppercase type label,
/// and (optionally) a right-aligned timestamp.
///
/// Matches `.note .head` in `mobile.css`:
/// - 8pt colored dot (semantic pigment)
/// - Inter 10pt 700 weight, uppercase, 0.08em tracking, `fg-2` color
/// - Time in monospace, right-aligned via margin-left: auto
struct TypeBadge: View {
    let type: NoteType
    /// Optional timestamp. Pass `nil` to omit the time column.
    let time: String?

    init(type: NoteType, time: String? = nil) {
        self.type = type
        self.time = time
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(type.color)
                .frame(width: 8, height: 8)
            Text(type.title)
                .font(.DS.sans(size: 10, weight: .bold))
                .tracking(0.8)  // 0.08em at 10pt = 0.8pt
                .textCase(.uppercase)
                .foregroundStyle(Color.DS.fg2)
            Spacer(minLength: 8)
            if let time {
                Text(time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.DS.fg2)
            }
        }
    }
}

#Preview("With times") {
    VStack(alignment: .leading, spacing: 10) {
        TypeBadge(type: .workout, time: "7:30 AM")
        TypeBadge(type: .meal, time: "12:15 PM")
        TypeBadge(type: .sleep, time: "11:02 PM")
        TypeBadge(type: .mood, time: "9:45 AM")
        TypeBadge(type: .activity, time: "6:20 PM")
    }
    .padding(20)
    .frame(width: 320, alignment: .leading)
    .background(Color.DS.bg2)
    .padding(20)
    .background(Color.DS.bg1)
}

#Preview("No times") {
    VStack(alignment: .leading, spacing: 10) {
        TypeBadge(type: .workout)
        TypeBadge(type: .meal)
    }
    .padding(20)
    .frame(width: 320, alignment: .leading)
    .background(Color.DS.bg2)
    .padding(20)
    .background(Color.DS.bg1)
}

#Preview("Dark") {
    VStack(alignment: .leading, spacing: 10) {
        TypeBadge(type: .workout, time: "7:30 AM")
        TypeBadge(type: .sleep, time: "11:02 PM")
        TypeBadge(type: .activity, time: "6:20 PM")
    }
    .padding(20)
    .frame(width: 320, alignment: .leading)
    .background(Color.DS.bg2)
    .padding(20)
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}
