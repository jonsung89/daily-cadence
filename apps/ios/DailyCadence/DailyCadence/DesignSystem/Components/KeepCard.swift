import SwiftUI

/// A Google Keep-style card — varied content heights, type-tinted background,
/// pigment-colored head label.
///
/// Matches `.keep` in `mobile.css` plus the inline styles in
/// `design/claude-design-system/ui_kits/mobile/Timeline.jsx`:
/// - Background: note type's soft color at `0x55` alpha (≈ 0.333 opacity)
/// - Border: note type's pigment color at `0x33` alpha (≈ 0.2 opacity)
/// - 10pt radius, 10pt top/bottom × 12pt left/right padding, 4pt vertical gap
/// - Head: 7pt pigment-colored dot + 9pt uppercase 700-weight pigment label,
///   0.08em tracking
/// - Five content variants (`.text` / `.stat` / `.list` / `.quote` — plus
///   `.text` with no message acting as the `.title`-only kind)
///
/// Drag-to-reorder (the `.keep.drag` CSS class) is deferred to a later pass.
struct KeepCard: View {
    let note: MockNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            head
            contentView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundLayer)
        .overlay(
            // Border keeps the type's pigment so the data legend reads even
            // when the user picks a custom background that doesn't match
            // the type's softColor.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(note.type.color.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Resolves background based on the note's resolved style. Falls back to
    /// the type's softColor when no background is set.
    @ViewBuilder
    private var backgroundLayer: some View {
        let style = note.resolvedBackgroundStyle
        switch style {
        case .none:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(note.type.softColor.opacity(0.333))
        case .color(let swatch):
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(swatch.color().opacity(0.333))
        case .image(let data, let opacity):
            ZStack {
                // Default surface underneath so reduced opacity reads as
                // "image over warm cream" not "image over the page bg."
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.DS.bg2)
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

    private var head: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(note.type.color)
                .frame(width: 7, height: 7)
            Text(note.type.title)
                .font(.DS.sans(size: 9, weight: .bold))
                .tracking(0.72)  // 0.08em at 9pt
                .textCase(.uppercase)
                .foregroundStyle(note.type.color)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var contentView: some View {
        switch note.content {
        case .text(let title, let message):
            textContent(title: title, message: message)
        case .stat(let title, let value, let sub):
            statContent(title: title, value: value, sub: sub)
        case .list(let title, let items):
            listContent(title: title, items: items)
        case .quote(let text):
            quoteContent(text: text)
        }
    }

    // MARK: - Variants

    private func textContent(title: String, message: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(note.titleStyle.resolvedFont(defaultFontId: "inter", size: 14, weight: .semibold))
                .foregroundStyle(note.titleStyle.resolvedColor(default: Color.DS.ink))
                .lineSpacing(14 * 0.3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let message, !message.isEmpty {
                Text(message)
                    .font(note.messageStyle.resolvedFont(defaultFontId: "inter", size: 12, weight: .regular))
                    .foregroundStyle(note.messageStyle.resolvedColor(default: Color.DS.fg2))
                    .lineSpacing(12 * 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statContent(title: String, value: String, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.DS.sans(size: 14, weight: .semibold))
                .foregroundStyle(Color.DS.ink)
            Text(value)
                .font(.DS.serif(size: 24, weight: .bold))
                .tracking(-0.24)
                .foregroundStyle(Color.DS.ink)
                .padding(.top, 2)
            if let sub {
                Text(sub)
                    .font(.DS.sans(size: 12, weight: .regular))
                    .foregroundStyle(Color.DS.fg2)
                    .padding(.top, 2)
            }
        }
    }

    private func listContent(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.DS.sans(size: 14, weight: .semibold))
                .foregroundStyle(Color.DS.ink)
                .padding(.bottom, 2)
            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.DS.border2, lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                    Text(item)
                        .font(.DS.sans(size: 12, weight: .regular))
                        .foregroundStyle(Color.DS.ink)
                }
            }
        }
    }

    private func quoteContent(text: String) -> some View {
        Text("\u{201C}\(text)\u{201D}")
            .font(.DS.serif(size: 14, weight: .regular))
            .italic()
            .foregroundStyle(Color.DS.ink)
            .lineSpacing(14 * 0.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview("Variants, light") {
    ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            KeepCard(note: MockNote(
                time: "6:45 AM", type: .sleep,
                content: .stat(title: "Slept", value: "7h 14m", sub: "Woke once around 3am")
            ))
            KeepCard(note: MockNote(
                time: "7:32 AM", type: .workout,
                content: .text(
                    title: "Easy run · 35 min",
                    message: "Felt strong. Legs tight early on."
                )
            ))
            KeepCard(note: MockNote(
                time: "8:30 AM", type: .meal,
                content: .list(title: "Breakfast", items: ["Oatmeal", "Blueberries", "Coffee"])
            ))
            KeepCard(note: MockNote(
                time: "10:05 AM", type: .mood,
                content: .text(title: "Focused")
            ))
            KeepCard(note: MockNote(
                time: "6:20 PM", type: .mood,
                content: .quote(text: "Noticed I'm less anxious on running days.")
            ))
        }
        .padding(20)
    }
    .background(Color.DS.bg1)
}

#Preview("Variants, dark") {
    ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            KeepCard(note: MockNote(
                time: "6:45 AM", type: .sleep,
                content: .stat(title: "Slept", value: "7h 14m", sub: "Woke once around 3am")
            ))
            KeepCard(note: MockNote(
                time: "8:30 AM", type: .meal,
                content: .list(title: "Breakfast", items: ["Oatmeal", "Blueberries", "Coffee"])
            ))
            KeepCard(note: MockNote(
                time: "6:20 PM", type: .mood,
                content: .quote(text: "Noticed I'm less anxious on running days.")
            ))
        }
        .padding(20)
    }
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}
