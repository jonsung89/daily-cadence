import Foundation
import SwiftUI

/// One block in a text note's body — either a paragraph of rich text or
/// an inline media item. Phase E.5.18 introduces this to support
/// journal-style mixed text + media notes (like Apple Notes / Day One /
/// Notion): the user types, drops in a photo, keeps typing, drops in
/// another photo. The note's body is a flat list of these blocks
/// rendered top-to-bottom in both the editor and the card view.
///
/// **Why not a single AttributedString with NSTextAttachment runs.**
/// SwiftUI's read-only `Text(_:AttributedString)` doesn't render
/// NSTextAttachment images — that path requires UITextView wrapping for
/// both edit and read. The block model delivers the same user-facing
/// behavior with native SwiftUI components: each `.paragraph` is a
/// standalone `TextEditor` (in the editor) / `Text` (in cards), each
/// `.media` is a standalone Image / video poster. Vertically stacked.
///
/// **Identity (`UUID`) is stable across edits** so SwiftUI's `ForEach`
/// can identify each block correctly when the user reorders / inserts /
/// deletes mid-list. The id survives content edits — only block creation
/// generates a new id.
struct TextBlock: Hashable, Identifiable {
    let id: UUID
    var kind: Kind

    enum Kind: Hashable {
        /// Rich text paragraph. May be empty (a freshly inserted
        /// paragraph block waiting for the user to type). Per-character
        /// attributes (font / foreground color) carry the existing
        /// Phase E.2 rich-text behavior.
        case paragraph(AttributedString)

        /// Inline photo or video, with a user-controlled display size.
        /// `MediaPayload` is the same value type used by bare media notes
        /// (Phase E.3), so the import / playback / fullscreen pipeline
        /// is shared.
        case media(MediaPayload, size: MediaBlockSize)
    }

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    // MARK: - Convenience constructors

    static func paragraph(_ text: AttributedString = AttributedString("")) -> TextBlock {
        TextBlock(kind: .paragraph(text))
    }

    static func media(_ payload: MediaPayload, size: MediaBlockSize = .medium) -> TextBlock {
        TextBlock(kind: .media(payload, size: size))
    }

    // MARK: - Accessors

    /// True for a `.paragraph` block whose text is empty. Used by the
    /// editor to suppress placeholder ghosts on intermediate empty
    /// blocks (only the trailing empty block shows the placeholder).
    var isEmptyParagraph: Bool {
        if case .paragraph(let text) = kind, text.characters.isEmpty {
            return true
        }
        return false
    }

    var isParagraph: Bool {
        if case .paragraph = kind { return true }
        return false
    }

    var isMedia: Bool {
        if case .media = kind { return true }
        return false
    }
}

/// User-controlled display size for an inline media block. Mirrors
/// Apple Notes' "View as Small / Medium / Large Image" menu — coarse
/// presets give meaningful control without the fiddly precision of
/// per-pixel resize handles. The Phase 1 sweet spot for a one-handed
/// journaling flow.
///
/// `widthFraction` is multiplied by the card's content width when
/// rendering. Heights remain proportional to the asset's aspect ratio.
enum MediaBlockSize: String, Hashable, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    /// Fraction of the card's content width.
    var widthFraction: CGFloat {
        switch self {
        case .small:  return 0.45
        case .medium: return 0.75
        case .large:  return 1.0
        }
    }

    /// How the block aligns within the card's content width when its
    /// rendered width is less than the full content width. Small + medium
    /// center for visual balance; large naturally fills the row.
    var horizontalAlignment: Alignment {
        switch self {
        case .small, .medium: return .center
        case .large:          return .leading  // fills the row anyway
        }
    }

    var title: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }
}
