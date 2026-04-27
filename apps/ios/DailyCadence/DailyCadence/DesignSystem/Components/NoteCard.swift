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
/// **Two scaffolds (Phase E.4):**
/// - **Text** — original layout: `TypeBadge` head + title + optional
///   message. Padded inside the rounded `bg-2` surface.
/// - **Media** (`isMediaNote == true`) — full-bleed: photo or video
///   poster fills the card, no `TypeBadge` head, no inner padding. Caption
///   sits in a gradient overlay at the bottom.
///
/// Both scaffolds share the rounded clip + 1pt border + level-1 shadow,
/// and both cap at `NoteCard.maxHeight`.
struct NoteCard: View {
    let type: NoteType
    let title: String
    let message: AttributedString?
    /// Optional timestamp shown in the head row. Pass `nil` if the surrounding
    /// container (e.g. `TimelineItem`) already shows the time.
    let time: String?
    /// Optional per-note background. `.none` uses the neutral default surface
    /// (`bg-2`); `.color` fills with the user-picked swatch at full opacity
    /// (Phase E.5.20 — WYSIWYG); `.image` renders a photo scaled-to-fill
    /// with user-chosen opacity.
    let background: NoteBackgroundStyle
    /// Optional font + color override for the title text. `nil` = card default.
    let titleStyle: TextStyle?
    /// Optional photo/video payload (Phase E.3). When non-nil, the card
    /// renders with the full-bleed media scaffold (no `TypeBadge` head,
    /// caption in a bottom gradient).
    let media: MediaPayload?
    /// Optional note id (Phase E.5.15). When provided, the card renders
    /// the pin overlay + `.contextMenu` (Pin / Delete). Previews and
    /// other synthetic callers omit this and get a static card.
    let noteId: UUID?
    /// Optional Delete callback fired from the `.contextMenu`. The
    /// parent screen owns the confirmation dialog; this is just the
    /// "user asked to delete" notification.
    let onRequestDelete: ((UUID) -> Void)?

    /// Optional tap callback (Phase F.1.0). Fires on tap of the text
    /// scaffold; the media scaffold keeps its existing
    /// "tap → open `MediaViewerScreen`" behavior. Parent screens pass
    /// this to open the editor in edit mode for the tapped note. Nil
    /// = card is non-tappable (preview / static usage).
    let onTap: (() -> Void)?

    /// Maximum rendered height for any timeline card. Tall portrait media
    /// or long messages are clipped to this. Slightly higher than `KeepCard`
    /// since the timeline is single-column and cards can afford more height.
    static let maxHeight: CGFloat = 520

    @State private var isMediaViewerPresented = false

    init(
        type: NoteType,
        title: String,
        message: AttributedString? = nil,
        time: String? = nil,
        background: NoteBackgroundStyle = .none,
        titleStyle: TextStyle? = nil,
        media: MediaPayload? = nil,
        noteId: UUID? = nil,
        onRequestDelete: ((UUID) -> Void)? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.type = type
        self.title = title
        self.message = message
        self.time = time
        self.background = background
        self.titleStyle = titleStyle
        self.media = media
        self.noteId = noteId
        self.onRequestDelete = onRequestDelete
        self.onTap = onTap
    }

    /// Reads pin state through `PinStore.shared` inside `body` so the card
    /// re-renders when pin state flips. `nil` `noteId` => not pinnable.
    private var isPinned: Bool {
        guard let noteId else { return false }
        return PinStore.shared.isPinned(noteId)
    }

    var body: some View {
        Group {
            if let media {
                mediaScaffold(media)
            } else {
                textScaffold
                    // Phase F.1.0 — tap a text card to edit. The media
                    // scaffold keeps its own tap → MediaViewerScreen.
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?() }
            }
        }
        // See `KeepCard` for the rationale — `fixedSize(vertical: true)`
        // collapses cards to their intrinsic height before the maxHeight
        // cap kicks in, preventing the parent layout from inflating
        // short cards.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: Self.maxHeight)
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
        // Phase E.5.15 — pin glyph as status indicator only. Shown
        // exclusively when the note IS pinned (tap to unpin). Pinning
        // an unpinned note happens via `.contextMenu`. Keeps the
        // Timeline visually quiet for the common case where most cards
        // aren't pinned.
        .overlay(alignment: .topTrailing) {
            if let noteId, isPinned {
                PinButton(isPinned: true) {
                    PinStore.shared.togglePin(noteId)
                }
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(media != nil ? 0.85 : 0)
                        .frame(width: 28, height: 28)
                )
                .padding(4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: isPinned)
        .fullScreenCover(isPresented: $isMediaViewerPresented) {
            if let media {
                MediaViewerScreen(media: media)
            }
        }
        .contextMenu {
            if let noteId {
                Button {
                    PinStore.shared.togglePin(noteId)
                } label: {
                    Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
                }
                if let onRequestDelete {
                    Button(role: .destructive) {
                        onRequestDelete(noteId)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Text scaffold

    private var textScaffold: some View {
        VStack(alignment: .leading, spacing: 6) {
            TypeBadge(type: type, time: time)
            Text(title)
                .font(titleStyle.resolvedFont(defaultFontId: "inter", size: 16, weight: .semibold))
                .foregroundStyle(titleStyle.resolvedColor(default: Color.DS.ink))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let message, !message.characters.isEmpty {
                Text(message)
                    .font(.DS.sans(size: 14, weight: .regular))
                    .foregroundStyle(Color.DS.fg2)
                    .lineSpacing(14 * 0.5)  // line-height 1.5 ≈ 7pt extra line spacing
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Media scaffold (full-bleed media + caption-below)

    /// **Phase E.4.1 layout.** Image at top fills the column at native
    /// aspect ratio (no letterbox, `aspectRatio: .fill`); caption — when
    /// present — sits on the `bg-2` surface beneath the image, padded.
    private func mediaScaffold(_ media: MediaPayload) -> some View {
        VStack(spacing: 0) {
            mediaImageRow(media)
            if let caption = media.caption, !caption.isEmpty {
                Text(caption)
                    .font(.DS.sans(size: 13, weight: .regular))
                    .foregroundStyle(Color.DS.ink)
                    .lineSpacing(13 * 0.4)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.DS.bg2)
            }
        }
    }

    /// Same explicit `GeometryReader`-based sizing as `KeepCard.mediaImageRow`
    /// — see the comment there for the rationale. Phase E.4.2 fixed a bug
    /// where the asset rendered narrower than the timeline column.
    private func mediaImageRow(_ media: MediaPayload) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width / media.aspectRatio
            ZStack {
                Color.DS.bg2
                if let poster = mediaPosterImage(media) {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                }
                if media.kind == .video {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 48, height: 48)
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.DS.ink)
                            .offset(x: 1.5)
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

    private func mediaPosterImage(_ media: MediaPayload) -> UIImage? {
        if let poster = media.posterData, let img = UIImage(data: poster) { return img }
        return UIImage(data: media.data)
    }

    @ViewBuilder
    private var customBackgroundLayer: some View {
        switch background {
        case .none:
            EmptyView()
        case .color(let swatch):
            // Phase E.5.20 — full-opacity user-picked swatch (WYSIWYG).
            // Matches the picker preview; the user can pick a contrasting
            // text color via the editor's style toolbar if their swatch
            // demands it. Same change as KeepCard.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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

#Preview("Light") {
    VStack(spacing: 14) {
        NoteCard(
            type: .workout,
            title: "Leg day — felt strong",
            message: AttributedString("PR attempt on squats today. Bumped from 215 to 225 for 4×6."),
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
            message: AttributedString("Slept through the night. Woke up refreshed."),
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
            message: AttributedString("PR attempt on squats today. Bumped from 215 to 225 for 4×6."),
            time: "7:32 AM"
        )
        NoteCard(
            type: .activity,
            title: "4.2 mile walk",
            message: AttributedString("Morning loop around the neighborhood."),
            time: "6:20 AM"
        )
    }
    .padding(20)
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}
