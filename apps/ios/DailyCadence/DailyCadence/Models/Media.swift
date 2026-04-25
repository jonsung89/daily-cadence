import Foundation
import CoreGraphics

/// A photo or video attached to a `MockNote.Content.media` note.
///
/// Phase E.3 stores media inline as `Data` for the in-memory MVP — same
/// pattern as `MockNote.ImageBackground`. When Supabase Storage lands
/// (Phase F+), `data` becomes "bytes loaded from a remote URL" and the
/// case shape stays the same.
///
/// **Posters.** For videos we cache a single first-frame `posterData`
/// generated at import time so cards render instantly without spinning up
/// `AVPlayer`. Image notes don't use the poster slot — the data is the
/// image.
///
/// **Aspect ratio.** Stored explicitly (width / height) so the card layout
/// can size the media area without decoding the asset on every render.
struct MediaPayload: Hashable {
    enum Kind: String, Hashable, Codable {
        case image
        case video
    }

    let kind: Kind
    /// The bytes of the asset itself — JPEG/PNG/HEIC for images, MP4/MOV
    /// for videos. iOS decodes via `UIImage(data:)` (images) or
    /// `AVAsset(url:)` after writing to a temp file (videos).
    let data: Data
    /// First-frame thumbnail for videos; `nil` for images.
    let posterData: Data?
    /// width / height. Used to lay out the media area in cards without
    /// touching the asset on every render. Clamped to a sensible range
    /// (0.4 ... 2.5) at construction so a malformed asset can't break the
    /// 2-col masonry layout.
    let aspectRatio: CGFloat
    /// Optional caption shown below the media in cards and as the body
    /// text in the timeline view.
    let caption: String?

    init(
        kind: Kind,
        data: Data,
        posterData: Data? = nil,
        aspectRatio: CGFloat,
        caption: String? = nil
    ) {
        self.kind = kind
        self.data = data
        self.posterData = posterData
        // Cards lay this out in a 2-col masonry capped at ~400pt — clamp
        // extreme aspect ratios so a panorama or a portrait asset doesn't
        // collapse the layout.
        self.aspectRatio = min(max(aspectRatio, 0.4), 2.5)
        if let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            self.caption = trimmed
        } else {
            self.caption = nil
        }
    }
}
