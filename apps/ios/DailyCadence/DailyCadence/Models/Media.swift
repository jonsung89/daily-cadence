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
    /// Inline asset bytes — populated for newly-imported media notes
    /// (just picked from the photo library), `nil` for fetched-from-server
    /// media. When `nil`, callers should resolve via `ref` through
    /// `MediaResolver`. JPEG/PNG/HEIC for images, MP4/MOV for videos.
    let data: Data?
    /// First-frame poster for videos; `nil` for images. Inline bytes,
    /// populated for newly-imported video; `nil` for fetched videos
    /// (use `posterRef` instead).
    let posterData: Data?
    /// Phase F.1.1b — small (~600px) HEIC version of the asset for
    /// images. Cards in the timeline / Cards grid render this; the
    /// fullscreen viewer uses `data` (or `ref`). Cuts grid-view egress
    /// 5-10× since most user time is spent scanning cards. `nil` for
    /// videos (use `posterData`/`posterRef` instead) and for fetched
    /// images (use `thumbnailRef`).
    let thumbnailData: Data?
    /// width / height. Used to lay out the media area in cards without
    /// touching the asset on every render. Clamped to a sensible range
    /// (0.4 ... 2.5) at construction so a malformed asset can't break the
    /// 2-col masonry layout.
    let aspectRatio: CGFloat
    /// Optional caption shown below the media in cards and as the body
    /// text in the timeline view.
    let caption: String?

    /// Phase F.1.2.exifdate — wall-clock moment the asset was captured,
    /// extracted from EXIF `DateTimeOriginal` for image library imports
    /// or set to `Date()` at camera-capture time. For video, comes from
    /// `AVAsset.creationDate` when available. Surfaced in
    /// `MediaViewerScreen` chrome as a small info label so the user
    /// sees when the moment was taken (vs. when the note was logged).
    /// `nil` for assets without metadata or for notes saved before this
    /// field landed.
    let capturedAt: Date?

    /// Phase F.1.1 — Storage ref for the full asset. Populated when this
    /// payload was decoded from a fetched note's body, or after a
    /// background upload completes for a newly-imported note. `nil` for
    /// session-only media that hasn't uploaded yet.
    let ref: MediaRef?
    /// Phase F.1.1 — Storage ref for the video poster. Image notes
    /// leave this nil. Video notes fetched from server populate it so
    /// cards can render the poster without fetching the full asset.
    let posterRef: MediaRef?
    /// Phase F.1.1b — Storage ref for the small image thumbnail. Image
    /// notes populate this; video notes leave it nil. Cards prefer this
    /// over `ref` to keep grid-view egress low.
    let thumbnailRef: MediaRef?

    init(
        kind: Kind,
        data: Data? = nil,
        posterData: Data? = nil,
        thumbnailData: Data? = nil,
        aspectRatio: CGFloat,
        caption: String? = nil,
        capturedAt: Date? = nil,
        ref: MediaRef? = nil,
        posterRef: MediaRef? = nil,
        thumbnailRef: MediaRef? = nil
    ) {
        self.kind = kind
        self.data = data
        self.posterData = posterData
        self.thumbnailData = thumbnailData
        // Cards lay this out in a 2-col masonry capped at ~400pt — clamp
        // extreme aspect ratios so a panorama or a portrait asset doesn't
        // collapse the layout.
        self.aspectRatio = min(max(aspectRatio, 0.4), 2.5)
        if let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            self.caption = trimmed
        } else {
            self.caption = nil
        }
        self.capturedAt = capturedAt
        self.ref = ref
        self.posterRef = posterRef
        self.thumbnailRef = thumbnailRef
    }
}
