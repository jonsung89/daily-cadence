import SwiftUI

/// A single note card on the daily timeline.
///
/// Matches `.note` in `design/claude-design-system/ui_kits/mobile/mobile.css`:
/// - `bg-2` surface (white in light, warm near-black in dark)
/// - 1pt `border-1`
/// - 12pt corner radius
/// - 14pt top/bottom × 16pt left/right padding
/// - 6pt vertical gap between head / title / message
/// - Level-1 shadow (resting card)
///
/// The card is intentionally content-agnostic — callers compose a head (via
/// `TypeBadge`), a title, and an optional message. Photo attachments and
/// swipe actions live at the `TimelineItem` / list-row layer.
///
/// > Note: The parameter is named `message` (not `body`) to avoid colliding
/// > with SwiftUI's `View.body` requirement.
struct NoteCard: View {
    let type: NoteType
    let title: String
    let message: String?
    /// Optional timestamp shown in the head row. Pass `nil` if the surrounding
    /// container (e.g. `TimelineItem`) already shows the time.
    let time: String?
    /// Optional per-note background. `.none` uses the neutral default surface
    /// (`bg-2`); `.color` applies a swatch at 0.333 opacity over the default;
    /// `.image` renders a photo scaled-to-fill with user-chosen opacity.
    let background: NoteBackgroundStyle
    /// Optional font + color override for the title text. `nil` = card default.
    let titleStyle: TextStyle?
    /// Optional font + color override for the message text. `nil` = card default.
    let messageStyle: TextStyle?

    init(
        type: NoteType,
        title: String,
        message: String? = nil,
        time: String? = nil,
        background: NoteBackgroundStyle = .none,
        titleStyle: TextStyle? = nil,
        messageStyle: TextStyle? = nil
    ) {
        self.type = type
        self.title = title
        self.message = message
        self.time = time
        self.background = background
        self.titleStyle = titleStyle
        self.messageStyle = messageStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TypeBadge(type: type, time: time)
            Text(title)
                .font(titleStyle.resolvedFont(defaultFontId: "inter", size: 16, weight: .semibold))
                .foregroundStyle(titleStyle.resolvedColor(default: Color.DS.ink))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let message, !message.isEmpty {
                Text(message)
                    .font(messageStyle.resolvedFont(defaultFontId: "inter", size: 14, weight: .regular))
                    .foregroundStyle(messageStyle.resolvedColor(default: Color.DS.fg2))
                    .lineSpacing(14 * 0.5)  // line-height 1.5 ≈ 7pt extra line spacing
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            // Default surface — always present so tinted overlays preserve
            // contrast against the cream/ink page background underneath.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.DS.bg2)
        )
        .background(customBackgroundLayer)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.DS.border1, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .dsShadow(.level1)
    }

    @ViewBuilder
    private var customBackgroundLayer: some View {
        switch background {
        case .none:
            EmptyView()
        case .color(let swatch):
            // Tinted overlay above bg-2 — design system's "no full-saturation
            // large fills" rule keeps this at 0.333 opacity.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(swatch.color().opacity(0.333))
        case .image(let data, let opacity):
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(opacity)
                    .clipped()
            }
        }
    }
}

#Preview("Light") {
    VStack(spacing: 14) {
        NoteCard(
            type: .workout,
            title: "Leg day — felt strong",
            message: "PR attempt on squats today. Bumped from 215 to 225 for 4×6.",
            time: "7:32 AM"
        )
        NoteCard(
            type: .meal,
            title: "Sushi bowl with coworkers",
            time: "12:15 PM"
        )
        NoteCard(
            type: .sleep,
            title: "7h 18m",
            message: "Slept through the night. Woke up refreshed.",
            time: "6:45 AM"
        )
        NoteCard(
            type: .mood,
            title: "Focused and calm",
            time: "9:00 AM"
        )
    }
    .padding(20)
    .background(Color.DS.bg1)
}

#Preview("Dark") {
    VStack(spacing: 14) {
        NoteCard(
            type: .workout,
            title: "Leg day — felt strong",
            message: "PR attempt on squats today. Bumped from 215 to 225 for 4×6.",
            time: "7:32 AM"
        )
        NoteCard(
            type: .activity,
            title: "4.2 mile walk",
            message: "Morning loop around the neighborhood.",
            time: "6:20 AM"
        )
    }
    .padding(20)
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}
