import SwiftUI

/// The head row of a `NoteCard`: a colored dot, an uppercase type label,
/// and (optionally) a right-aligned timestamp.
///
/// **Phase E.5.14 — sizing + color refresh.** Bumped from 8pt dot /
/// 10pt grey label to **10pt dot / 11pt colored label** so the type is
/// the visual anchor of a Timeline card (the user reads "Workout" before
/// landing on the title). Time stays in `fg-2` since it's secondary
/// info that doesn't deserve the colored treatment.
///
/// Originally derived from `.note .head` in `mobile.css`; the css spec
/// is now superseded by this file for the iOS build. KeepCard's `head`
/// (Board view) uses the same colored-label pattern with slightly
/// smaller sizing for the denser masonry context.
struct TypeBadge: View {
    let type: NoteType
    /// Optional timestamp. Pass `nil` to omit the time column.
    let time: String?

    init(type: NoteType, time: String? = nil) {
        self.type = type
        self.time = time
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(type.color)
                .frame(width: 10, height: 10)
            Text(type.title)
                .font(.DS.sans(size: 11, weight: .bold))
                .tracking(0.88)  // 0.08em at 11pt
                .textCase(.uppercase)
                .foregroundStyle(type.color)
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
