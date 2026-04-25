import SwiftUI

/// A Google Keep-style card — varied content heights, type-tinted background,
/// pigment-colored head label.
///
/// **Two scaffolds based on `note.kind`:**
///
/// - **Text scaffold** (`.text`) — the original Keep card: `bg-2` surface
///   with the type's pigment at 0.333 opacity, 1pt border at 0.2 opacity,
///   pigment-colored type-chip head, then the content variant
///   (text/stat/list/quote). Padded inside the card border.
///
/// - **Media scaffold** (`.photo` / `.video`) — full-bleed: the photo or
///   video fills the entire card with **no type chip, no padding, no
///   border**. The card's identity *is* the asset. Caption (when present)
///   sits at the bottom in a subtle gradient overlay so it's readable
///   regardless of the underlying image. Tapping anywhere on the media
///   surface opens `MediaViewerScreen`.
///
/// **Phase E.3 → E.4** introduced this split. Before E.4 a media note
/// rendered with the same text scaffold (head + media area inset) which
/// added unnecessary chrome and felt foreign on a photo card.
///
/// **Max height (`KeepCard.maxHeight`)** still applies to both scaffolds
/// so a single card can't dominate the 2-col masonry.
///
/// Drag-to-reorder (the `.keep.drag` CSS class) is deferred to a later pass.
struct KeepCard: View {
    let note: MockNote

    /// Maximum rendered height for any card in the Board grid. Tuned so a
    /// long-message text card or a tall portrait photo doesn't push the
    /// neighboring column off-screen.
    static let maxHeight: CGFloat = 480

    @State private var isMediaViewerPresented = false

    var body: some View {
        Group {
            if note.isMediaNote, let media = note.mediaPayload {
                mediaScaffold(media)
            } else {
                textScaffold
            }
        }
        // Phase E.4.4 — `fixedSize(vertical: true)` forces the card to
        // its INTRINSIC height even when the parent VStack column has
        // spare vertical space to give. Without this, `.frame(maxHeight:)`
        // alone reports a flexible-up-to-480 preferred size, and SwiftUI's
        // VStack happily inflates short cards to fill the column —
        // producing the "lots of empty space inside the card" bug.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: Self.maxHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .fullScreenCover(isPresented: $isMediaViewerPresented) {
            if let media = note.mediaPayload {
                MediaViewerScreen(media: media)
            }
        }
    }

    // MARK: - Text scaffold (original Keep card)

    private var textScaffold: some View {
        VStack(alignment: .leading, spacing: 4) {
            head
            contentView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(textBackgroundLayer)
        .overlay(
            // Border keeps the type's pigment so the data legend reads even
            // when the user picks a custom background that doesn't match
            // the type's softColor.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(note.type.color.opacity(0.2), lineWidth: 1)
        )
    }

    /// Resolves background based on the note's resolved style. Always layers
    /// the chosen tint/image on top of a solid `bg-2` base so the card stays
    /// opaque even when stacked under other cards (matches the design
    /// system's "white surface on cream background" rule).
    @ViewBuilder
    private var textBackgroundLayer: some View {
        let style = note.resolvedBackgroundStyle
        ZStack {
            // Solid base — keeps the card opaque so layered cards in
            // StackedBoardView don't see through to each other.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.DS.bg2)

            switch style {
            case .none:
                // Default tint matches the type's pigment color at the same
                // 0.333 opacity used for user-picked swatches — so a fresh
                // note "with a tag" already reads as that tag's color.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(note.type.color.opacity(0.333))
            case .color(let swatch):
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        case .media:
            // Should not reach here — body's `Group { … }` routes media
            // notes to `mediaScaffold`. Render nothing as a defensive
            // fallback so a future refactor that lands here doesn't crash.
            EmptyView()
        }
    }

    // MARK: - Variants

    private func textContent(title: String, message: AttributedString?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(note.titleStyle.resolvedFont(defaultFontId: "inter", size: 14, weight: .semibold))
                .foregroundStyle(note.titleStyle.resolvedColor(default: Color.DS.ink))
                .lineSpacing(14 * 0.3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let message, !message.characters.isEmpty {
                Text(message)
                    .font(.DS.sans(size: 12, weight: .regular))
                    .foregroundStyle(Color.DS.fg2)
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

    // MARK: - Media scaffold (full-bleed media + caption-below)

    /// **Phase E.4.1 layout.** Two stacked rows inside the rounded card:
    ///
    /// 1. The asset (image / video poster) fills the column edge-to-edge
    ///    at its native aspect ratio — `aspectRatio(media.aspectRatio,
    ///    contentMode: .fill)` so the image *covers* the cell without
    ///    letterbox, which addresses the "image isn't filling the cell"
    ///    feedback from earlier rounds.
    /// 2. Optional caption text sits **below** the image (not overlayed
    ///    on it) on the card's `bg-2` surface, padded.
    ///
    /// Tapping the image opens `MediaViewerScreen`. The caption row isn't
    /// tappable on its own — it shares the card's outer accessibility
    /// element instead.
    private func mediaScaffold(_ media: MediaPayload) -> some View {
        VStack(spacing: 0) {
            mediaImageRow(media)
            if let caption = media.caption, !caption.isEmpty {
                Text(caption)
                    .font(.DS.sans(size: 12, weight: .regular))
                    .foregroundStyle(Color.DS.ink)
                    .lineSpacing(12 * 0.4)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.DS.bg2)
            }
        }
    }

    /// Renders the asset filling the column at exactly `column_width ×
    /// (column_width / aspectRatio)`. Uses `GeometryReader` to read the
    /// column width and force the image to that explicit size — avoids
    /// the prior bug where `.aspectRatio(.fit)` + `.frame(maxWidth: .infinity)`
    /// could leave whitespace on either side of the asset when the parent
    /// also imposed a `maxHeight` bound (Phase E.4.2).
    private func mediaImageRow(_ media: MediaPayload) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width / media.aspectRatio
            ZStack {
                Color.DS.bg2
                if let posterImage = mediaPosterImage(media) {
                    Image(uiImage: posterImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                }
                if media.kind == .video {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 44, height: 44)
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.DS.ink)
                            .offset(x: 1.5)  // optical center for the play glyph
                    }
                }
            }
            .frame(width: width, height: height)
        }
        .aspectRatio(media.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { isMediaViewerPresented = true }
        .accessibilityLabel(media.kind == .video ? "Play video" : "Open photo")
        .accessibilityAddTraits(.isButton)
    }

    /// Returns the displayable poster image for a media payload — the
    /// `posterData` if present (videos), otherwise the asset itself
    /// decoded as a `UIImage` (images).
    private func mediaPosterImage(_ media: MediaPayload) -> UIImage? {
        if let poster = media.posterData, let img = UIImage(data: poster) { return img }
        return UIImage(data: media.data)
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
                    message: AttributedString("Felt strong. Legs tight early on.")
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
