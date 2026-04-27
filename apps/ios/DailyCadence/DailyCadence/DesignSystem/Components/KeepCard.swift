import SwiftUI
import TipKit

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
    /// Optional callback fired from the `.contextMenu` Delete action.
    /// The parent screen owns the actual deletion + confirmation dialog
    /// (Phase E.5.15). When `nil`, no Delete item appears in the menu.
    var onRequestDelete: ((MockNote) -> Void)? = nil
    /// Optional tap callback (Phase F.1.0). Fires on tap of the text
    /// scaffold; the media scaffold keeps its own
    /// "tap → open `MediaViewerScreen`" behavior. Parent screens pass
    /// this to open the editor in edit mode for the tapped note.
    var onTap: (() -> Void)? = nil
    /// Phase F.1.1b'.zoom — when set, the card uses the parent's shared
    /// namespace for matched-transition source and forwards media taps
    /// to the parent (which presents the viewer via NavigationStack
    /// push for the native zoom transition). When `nil`, the card falls
    /// back to its own `.fullScreenCover` — preserves preview /
    /// non-Timeline surfaces that haven't migrated.
    var mediaTapHandler: MediaTapHandler? = nil
    /// When false, suppresses the pin overlay and the card-owned
    /// `.contextMenu`. Used by previews and other surfaces that want a
    /// purely presentational card.
    var showsActions: Bool = true

    /// Maximum rendered height for any card in the Board grid. Tuned so a
    /// long-message text card or a tall portrait photo doesn't push the
    /// neighboring column off-screen.
    static let maxHeight: CGFloat = 480

    /// Donates the "user has used the context menu" TipKit event so the
    /// `CardActionsTip` discoverability hint disqualifies itself after
    /// the user has actually tried Pin or Delete. Fire-and-forget — the
    /// donation is async but doesn't need to block the action.
    private static func donateContextMenuUse() {
        Task { await CardActionsTip.userDidUseContextMenu.donate() }
    }

    @State private var isMediaViewerPresented = false
    /// Phase E.5.22 — drives the scheme-aware default-tint opacity so
    /// dark-mode cards don't read as muddy.
    @Environment(\.colorScheme) private var colorScheme

    /// Reads through `PinStore.shared.isPinned(note.id)` inside `body`
    /// so the Observation framework re-renders the card when pin state
    /// flips — same pattern as `Color.DS.sage` reading `ThemeStore`.
    private var isPinned: Bool {
        PinStore.shared.isPinned(note.id)
    }

    var body: some View {
        Group {
            if note.isMediaNote, let media = note.mediaPayload {
                mediaScaffold(media)
            } else {
                textScaffold
                    // Phase F.1.0 — tap a text card to edit. Media cards
                    // keep their existing tap → MediaViewerScreen.
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?() }
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
        // Phase E.5.15 — pin glyph as **status indicator only**. Shown
        // only when the card *is* pinned (Apple Notes / Mail flag /
        // iMessage pinned-conversation pattern); tapping the visible
        // glyph unpins. Pinning an unpinned card happens via the
        // `.contextMenu` Pin entry — no permanent chrome on every card.
        .overlay(alignment: .topTrailing) {
            if showsActions && isPinned {
                PinButton(isPinned: true) {
                    PinStore.shared.togglePin(note.id)
                }
                // For media cards the photo can render under the icon;
                // a thin material backdrop keeps the glyph readable
                // without mattering on text cards (where the surface is
                // already a calm tint).
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(note.isMediaNote ? 0.85 : 0)
                        .frame(width: 28, height: 28)
                )
                .padding(2)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: isPinned)
        .accessibilityElement(children: .combine)
        // Fallback presentation for surfaces that don't pass a
        // `mediaTapHandler` (previews, non-Timeline). When the handler
        // is set, the parent owns presentation + native zoom transition
        // and `isMediaViewerPresented` stays false here.
        .fullScreenCover(isPresented: $isMediaViewerPresented) {
            if let media = note.mediaPayload {
                MediaViewerScreen(media: media)
            }
        }
        .contextMenu {
            if showsActions {
                Button {
                    PinStore.shared.togglePin(note.id)
                    Self.donateContextMenuUse()
                } label: {
                    Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
                }
                if let onRequestDelete {
                    Button(role: .destructive) {
                        onRequestDelete(note)
                        Self.donateContextMenuUse()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
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
                // Phase E.5.22 — type-default tint with scheme-aware
                // opacity. Light: 0.333 (soft pastel over cream). Dark:
                // 0.18 (just a hint over the dark surface — matches
                // Notion / Bear / Apple Notes dark-mode card patterns
                // and avoids the muddy look from saturated tint over
                // dark bg2).
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(note.type.color.opacity(NoteType.defaultTintOpacity(for: colorScheme)))
            case .color(let swatch):
                // Phase E.5.20 — user-picked swatches render at FULL
                // opacity (WYSIWYG). The picker shows the swatch at full
                // saturation and the card now matches. Dark / bold
                // swatches make default ink text harder to read; the
                // user can pick a contrasting text color via the style
                // toolbar (Apple Notes / Bear pattern).
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(swatch.color())
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
        // Phase E.5.14 — bumped from 7pt dot / 9pt label to 9pt / 11pt
        // so the type indicator reads as a clear "header" on the card.
        //
        // **Phase E.5.22b — neutral label on tinted bg.** With the
        // bumped default tint opacity (0.6 light / 0.9 dark) the card
        // body fills with the type's color; rendering the label in the
        // same color makes it disappear. Switched to `Color.DS.ink`
        // (auto-adapts dark↔light) for high contrast against any
        // saturation. The colored DOT still carries identity.
        HStack(spacing: 7) {
            Circle()
                .fill(note.type.color)
                .frame(width: 9, height: 9)
            Text(note.type.title)
                .font(.DS.sans(size: 11, weight: .bold))
                .tracking(0.88)  // 0.08em at 11pt
                .textCase(.uppercase)
                .foregroundStyle(Color.DS.ink)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var contentView: some View {
        switch note.content {
        case .text(let title, let body):
            textContent(title: title, body: body)
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

    /// Phase E.5.18 — block-aware text body. Renders title + each block
    /// in vertical order: paragraph blocks render as `Text(AttributedString)`,
    /// media blocks render as inline images sized per `MediaBlockSize`.
    /// Tap an inline media block to open `MediaViewerScreen`. Blocks
    /// stack with consistent spacing so a "thought / photo / thought"
    /// rhythm reads cleanly.
    private func textContent(title: String, body: [TextBlock]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(note.titleStyle.resolvedFont(defaultFontId: "inter", size: 14, weight: .semibold))
                .foregroundStyle(note.titleStyle.resolvedColor(default: Color.DS.ink))
                .lineSpacing(14 * 0.3)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(body) { block in
                bodyBlockView(block)
            }
        }
    }

    @ViewBuilder
    private func bodyBlockView(_ block: TextBlock) -> some View {
        switch block.kind {
        case .paragraph(let text):
            if !text.characters.isEmpty {
                Text(text)
                    .font(.DS.sans(size: 12, weight: .regular))
                    // Phase E.5.22b — secondary body text on tinted cards.
                    // Bumped from `fg2` (warm gray) to `ink @ 0.75` so the
                    // text reads against saturated card bgs in both modes
                    // without being as loud as the title's full ink.
                    .foregroundStyle(Color.DS.ink.opacity(0.75))
                    .lineSpacing(12 * 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .media(let payload, let size):
            InlineMediaBlockView(payload: payload, size: size, cornerRadius: 8)
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
                    .foregroundStyle(Color.DS.ink.opacity(0.7))
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
                    // Phase E.5.22b — checkbox stroke uses ink @ 0.5
                    // (was `border2` warm-gray) so it contrasts against
                    // the tinted card bg in both light + dark modes.
                    // Border-token grays blended into the saturated fills.
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.DS.ink.opacity(0.5), lineWidth: 1.5)
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
                } else if media.ref != nil || media.posterRef != nil {
                    // Phase F.1.1: fetched-from-server media — bytes
                    // resolve via MediaResolver against ref/posterRef.
                    ResolvedMediaPoster(payload: media)
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
        .onTapGesture { handleMediaTap(media) }
        .modifier(MatchedGeometryModifier(handler: mediaTapHandler, id: note.id))
        .accessibilityLabel(media.kind == .video ? "Play video" : "Open photo")
        .accessibilityAddTraits(.isButton)
    }

    /// Routes the card's media tap. When the parent provided a
    /// `mediaTapHandler`, fires its callback (parent presents via
    /// NavigationStack push with native zoom transition). Otherwise
    /// falls back to the card-local `.fullScreenCover`.
    private func handleMediaTap(_ media: MediaPayload) {
        if let handler = mediaTapHandler {
            handler.onTap(media, note.id)
        } else {
            isMediaViewerPresented = true
        }
    }

    /// Returns the displayable poster image for a media payload.
    /// Phase F.1.1b — kind-aware: image prefers `thumbnailData` (small
    /// HEIC, ~80 KB) over `data` (full HEIC, ~400 KB); video uses
    /// `posterData`. Returns `nil` when the payload has no inline bytes
    /// (fetched-from-server media); the caller wraps a
    /// `ResolvedMediaPoster` that fetches via `MediaResolver`.
    private func mediaPosterImage(_ media: MediaPayload) -> UIImage? {
        switch media.kind {
        case .image:
            if let thumb = media.thumbnailData, let img = UIImage(data: thumb) { return img }
            return media.data.flatMap(UIImage.init(data:))
        case .video:
            if let poster = media.posterData, let img = UIImage(data: poster) { return img }
            return nil
        }
    }
}

// MARK: - Previews

#Preview("Variants, light") {
    ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            KeepCard(note: MockNote(
                occurredAt: MockNotes.todayAt(6, 45), type: .sleep,
                content: .stat(title: "Slept", value: "7h 14m", sub: "Woke once around 3am")
            ))
            KeepCard(note: MockNote(
                occurredAt: MockNotes.todayAt(7, 32), type: .workout,
                content: .text(
                    title: "Easy run · 35 min",
                    message: AttributedString("Felt strong. Legs tight early on.")
                )
            ))
            KeepCard(note: MockNote(
                occurredAt: MockNotes.todayAt(8, 30), type: .meal,
                content: .list(title: "Breakfast", items: ["Oatmeal", "Blueberries", "Coffee"])
            ))
            KeepCard(note: MockNote(
                occurredAt: MockNotes.todayAt(10, 5), type: .mood,
                content: .text(title: "Focused")
            ))
            KeepCard(note: MockNote(
                occurredAt: MockNotes.todayAt(18, 20), type: .mood,
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
                occurredAt: MockNotes.todayAt(6, 45), type: .sleep,
                content: .stat(title: "Slept", value: "7h 14m", sub: "Woke once around 3am")
            ))
            KeepCard(note: MockNote(
                occurredAt: MockNotes.todayAt(8, 30), type: .meal,
                content: .list(title: "Breakfast", items: ["Oatmeal", "Blueberries", "Coffee"])
            ))
            KeepCard(note: MockNote(
                occurredAt: MockNotes.todayAt(18, 20), type: .mood,
                content: .quote(text: "Noticed I'm less anxious on running days.")
            ))
        }
        .padding(20)
    }
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}
