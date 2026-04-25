import Foundation

/// A stand-in for the real `Note` model (which lands once we wire Supabase).
///
/// Each mock note carries a typed `Content` variant so the Timeline view and
/// the Keep-style card view can both render from a single source — the
/// timeline collapses every variant to title + optional message via
/// `timelineTitle` / `timelineMessage`, while the card view uses the variant
/// directly.
struct MockNote: Identifiable, Hashable {
    let id = UUID()
    let time: String
    let type: NoteType
    let content: Content
    /// Optional per-note background. `nil` means "use the default for this
    /// card type" (white surface in NoteCard, type-tinted softColor in KeepCard).
    let background: Background?
    /// Optional styling override for the note's title text (font + color).
    /// `nil` = use the card's default title styling. See `TextStyle`.
    let titleStyle: TextStyle?
    /// Optional styling override for the note's message/body text.
    /// `nil` = use the card's default message styling.
    let messageStyle: TextStyle?

    /// Typed content variants. Mirrors the `kind` field in the design
    /// system's `Timeline.jsx` keepItems (`title` / `body` / `stat` / `list`
    /// / `quote`). In production these will be driven by per-type editor
    /// fields on the real `Note` model.
    enum Content: Hashable {
        case text(title: String, message: String? = nil)
        case stat(title: String, value: String, sub: String? = nil)
        case list(title: String, items: [String])
        case quote(text: String)
    }

    /// Per-note background customization.
    ///
    /// - `.color(swatchId:)` references a swatch by id in `PaletteRepository`.
    ///   Storing the id (not the swatch itself) keeps notes durable across
    ///   palette JSON updates — stale ids gracefully resolve to no background.
    /// - `.image(_:)` carries an `ImageBackground` with the photo bytes and
    ///   user-chosen opacity. Phase D.2.1 ships PhotosPicker integration with
    ///   auto scale-to-fill rendering. Interactive pan/zoom crop is deferred
    ///   to D.2.2.
    enum Background: Hashable {
        case color(swatchId: String)
        case image(ImageBackground)
    }

    /// Photo-background payload. Stored inline as `Data` for the in-memory
    /// MVP; Phase F+ will swap this to a Supabase Storage URL once we wire
    /// real persistence (the case shape stays the same — `imageData` becomes
    /// "loaded data" backed by a remote fetch).
    struct ImageBackground: Hashable {
        /// Raw image bytes — JPEG / PNG / HEIC. iOS decodes via `UIImage(data:)`.
        let imageData: Data
        /// 0.0 ... 1.0. The image is rendered over `bg-2` so high opacity
        /// reads "photo on cream", lower opacity reads "subtle texture."
        var opacity: Double

        init(imageData: Data, opacity: Double = 1.0) {
            self.imageData = imageData
            self.opacity = max(0, min(1, opacity))
        }
    }

    init(
        time: String,
        type: NoteType,
        content: Content,
        background: Background? = nil,
        titleStyle: TextStyle? = nil,
        messageStyle: TextStyle? = nil
    ) {
        self.time = time
        self.type = type
        self.content = content
        self.background = background
        // Collapse "TextStyle with no overrides" to nil so empty styling
        // doesn't leak into persistence later.
        self.titleStyle = (titleStyle?.isEmpty ?? true) ? nil : titleStyle
        self.messageStyle = (messageStyle?.isEmpty ?? true) ? nil : messageStyle
    }

    // MARK: - Background resolution

    /// Resolves the configured background to a concrete `Swatch`, or returns
    /// `nil` if no swatch background is set (or the stored id has been
    /// removed from the palette since this note was authored).
    var backgroundSwatch: Swatch? {
        guard let background, case .color(let swatchId) = background else { return nil }
        return PaletteRepository.shared.swatch(id: swatchId)
    }

    /// Resolves to the image-background payload, or `nil` if no image is set.
    var backgroundImage: ImageBackground? {
        guard let background, case .image(let img) = background else { return nil }
        return img
    }

    /// One-step resolution to the renderable background style. This is what
    /// `NoteCard` / `KeepCard` consume — they don't know about
    /// `MockNote.Background`, only `NoteBackgroundStyle`. Stale swatch ids
    /// degrade to `.none` so cards fall back to their default surface.
    var resolvedBackgroundStyle: NoteBackgroundStyle {
        guard let background else { return .none }
        switch background {
        case .color(let swatchId):
            if let swatch = PaletteRepository.shared.swatch(id: swatchId) {
                return .color(swatch)
            }
            return .none
        case .image(let img):
            return .image(data: img.imageData, opacity: img.opacity)
        }
    }

    // MARK: - Timeline-view degradation
    //
    // The timeline is a simpler presentation: title + optional secondary
    // line. Map each content variant to those two slots.

    var timelineTitle: String {
        switch content {
        case .text(let title, _):     return title
        case .stat(let title, _, _):  return title
        case .list(let title, _):     return title
        case .quote(let text):        return "\u{201C}\(text)\u{201D}"
        }
    }

    var timelineMessage: String? {
        switch content {
        case .text(_, let message):
            return message
        case .stat(_, let value, let sub):
            if let sub { return "\(value) · \(sub)" }
            return value
        case .list(_, let items):
            return items.joined(separator: " · ")
        case .quote:
            return nil
        }
    }
}

enum MockNotes {
    /// A realistic sample day spanning all five default note types and all
    /// four card-content variants. A few notes carry a custom background to
    /// demonstrate Phase D.1 — the rest fall back to the type-default tinting.
    static let today: [MockNote] = [
        MockNote(
            time: "6:45 AM",
            type: .sleep,
            content: .stat(title: "Slept", value: "7h 14m", sub: "Woke once around 3am")
        ),
        MockNote(
            time: "7:32 AM",
            type: .workout,
            content: .text(
                title: "Easy run · 35 min",
                message: "Felt strong. Legs tight early on. Sunrise over the reservoir, cool air."
            )
        ),
        MockNote(
            time: "8:30 AM",
            type: .meal,
            content: .list(title: "Breakfast", items: ["Oatmeal", "Blueberries", "Coffee"])
        ),
        MockNote(
            time: "10:05 AM",
            type: .mood,
            content: .text(title: "Focused"),
            background: .color(swatchId: "pastel.mint"),  // demo: pastel mint highlight
            titleStyle: TextStyle(fontId: "playfair", colorId: "bold.emerald")  // demo: per-note styled title
        ),
        MockNote(
            time: "12:40 PM",
            type: .meal,
            content: .text(title: "Lunch", message: "Grain bowl, salmon, greens, tahini.")
        ),
        MockNote(
            time: "3:15 PM",
            type: .activity,
            content: .text(title: "Walk · 2.3 mi", message: "Park loop with a podcast.")
        ),
        MockNote(
            time: "6:20 PM",
            type: .mood,
            content: .quote(text: "Noticed I'm less anxious on running days."),
            background: .color(swatchId: "bold.cobalt")  // demo: bold cobalt under a quote
        ),
        MockNote(
            time: "9:30 PM",
            type: .mood,
            content: .text(title: "Wound down easy", message: "Read a few chapters. Early bedtime.")
        ),
        MockNote(
            time: "10:02 PM",
            type: .sleep,
            content: .text(title: "Lights out", message: "Planning 7h again.")
        ),
    ]
}
