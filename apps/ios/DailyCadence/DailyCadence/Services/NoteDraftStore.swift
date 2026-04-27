import SwiftUI

/// In-session draft cache for the New Note editor.
///
/// Why this exists: the `NoteEditorScreen` is presented as a sheet, and a
/// stray swipe down or tapping outside the sheet dismisses it instantly.
/// Without a draft cache, half-typed notes vanish on accidental dismiss.
/// This store keeps the in-progress fields alive across editor presentations
/// during a single app session so the user gets back exactly what they had.
///
/// **Lifecycle**
/// - **Save** — the editor builds a `MockNote`, hands it to `TimelineStore`,
///   then calls `clear()` here. Next presentation starts fresh.
/// - **Cancel** — the user explicitly tapped Cancel; `clear()`. (Cancel is
///   the *intentional* discard path.)
/// - **Background dismiss** (swipe / tap outside) — the editor goes away
///   but `clear()` is *not* called, so the state is restored on the next
///   open. This is the recovery path.
///
/// **Scope**
/// In-memory only — drafts don't survive app relaunch. UserDefaults / on-disk
/// persistence is a Phase F follow-up if it turns out users routinely lose
/// drafts to backgrounding. The current behavior covers the much more common
/// "I swiped the sheet away by accident" case.
///
/// **Why not lift state into `TimelineScreen`** — same effect, but `TimelineScreen`
/// is already a busy view; pulling all editor state up there muddies its
/// responsibility. The singleton keeps the editor's API small (no extra
/// bindings) and makes future persistence (Codable round-trip to UserDefaults
/// or a file) a one-place change.
@Observable
final class NoteDraftStore {
    static let shared = NoteDraftStore()

    /// Title text — plain `String`, styled by `titleStyle`.
    var title: String = ""

    /// **Phase E.5.18 — block-based body.** The note's body is a vertical
    /// list of text-and-media blocks. The editor renders each block as a
    /// dedicated widget (TextEditor for paragraph blocks, image preview
    /// for media blocks) and keeps this list in sync. Save serialises
    /// the list straight into `MockNote.Content.text(title:body:)`.
    ///
    /// The first paragraph block is always present so the editor has a
    /// guaranteed cursor target on a fresh open. Inserting media puts a
    /// new media block after the focused paragraph and a fresh empty
    /// paragraph after the media so the user can continue typing.
    var body: [TextBlock] = [.paragraph()]

    /// Tracks which paragraph block currently has the cursor. Drives
    /// the StyleToolbar's font/color/size targeting + `+image` insertion
    /// position. `nil` means no block is focused (editor just opened or
    /// keyboard dismissed).
    var focusedBlockId: UUID? = nil

    /// Selection state for the focused paragraph block's `TextEditor`.
    /// Reset when focus moves to a different block.
    var messageSelection: AttributedTextSelection = AttributedTextSelection()

    /// Mirrors the StyleToolbar's chip highlight for the message field. The
    /// AttributedString itself is the source of truth for what gets rendered.
    var messageFontId: String? = nil
    var messageColorId: String? = nil

    /// Current font size for the message editor — driven by the
    /// `VerticalSizeSlider`. Defaults to 16pt.
    var messageSize: CGFloat = 16

    /// Per-field title styling (font + color).
    var titleStyle: TextStyle? = nil

    /// Selected note type — defaults to `.mood` for max generality.
    var selectedType: NoteType = .general

    /// Optional per-note background (color swatch or photo).
    var background: MockNote.Background? = nil

    /// Phase F.0.3 — when set, overrides the editor's default save
    /// timestamp ("selected day, current time-of-day"). Bound to the
    /// editor's date+time picker. Cleared between editor sessions
    /// (the picker re-defaults from `TimelineStore.selectedDate` on open).
    var occurredAt: Date? = nil

    init() {}

    /// True when the user has typed nothing and made no styling choices.
    /// Used to skip the draft-restore branch on a totally fresh open so the
    /// editor still autofocuses cleanly.
    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        bodyIsEmpty &&
        background == nil &&
        titleStyle == nil &&
        messageFontId == nil &&
        messageColorId == nil
    }

    /// True when every block in `body` is an empty paragraph (no media,
    /// no text). Lets `isEmpty` distinguish "fresh draft" from "user
    /// typed something / attached a photo."
    private var bodyIsEmpty: Bool {
        body.allSatisfy { $0.isEmptyParagraph }
    }

    /// Reset the draft to its pristine state — called from Save (the note
    /// was committed to the timeline) and Cancel (intentional discard).
    func clear() {
        title = ""
        body = [.paragraph()]
        focusedBlockId = nil
        messageSelection = AttributedTextSelection()
        messageFontId = nil
        messageColorId = nil
        messageSize = 16
        titleStyle = nil
        selectedType = .general
        background = nil
        occurredAt = nil
    }

    // MARK: - Single-paragraph compatibility bridge
    //
    // Phase E.5.18 introduces the block model, but the existing
    // `NoteEditorScreen` flow operates on a single `message` AttributedString
    // (one big TextEditor). These computed properties bridge between the
    // legacy single-message API and the new block list by reading/writing
    // the first paragraph block. As long as the editor stays single-pane
    // (Phase E.5.18a), this lets us migrate without rewriting the editor in
    // the same round. Phase E.5.18b will replace these uses with proper
    // per-block bindings.

    /// Reads/writes the first paragraph block's text. If the body has no
    /// paragraph blocks (e.g. it starts with a media block), falls back
    /// to a fresh empty paragraph; setting then prepends one.
    var message: AttributedString {
        get {
            for block in body {
                if case .paragraph(let text) = block.kind {
                    return text
                }
            }
            return AttributedString("")
        }
        set {
            for i in body.indices {
                if case .paragraph = body[i].kind {
                    body[i].kind = .paragraph(newValue)
                    return
                }
            }
            // No paragraph block exists — prepend one with the new text.
            body.insert(.paragraph(newValue), at: 0)
        }
    }

    /// Reads/writes the **trailing** paragraph block's text — the
    /// "type after the images" editor (Phase E.5.18a). Only meaningful
    /// when `hasMedia` is true; otherwise this is the same paragraph
    /// as `message` and the editor only renders one TextEditor.
    var trailerMessage: AttributedString {
        get {
            for block in body.reversed() {
                if case .paragraph(let text) = block.kind {
                    return text
                }
            }
            return AttributedString("")
        }
        set {
            for i in body.indices.reversed() {
                if case .paragraph = body[i].kind {
                    body[i].kind = .paragraph(newValue)
                    return
                }
            }
            body.append(.paragraph(newValue))
        }
    }

    /// True when the body contains at least one media block. Drives
    /// whether the editor renders the trailing TextEditor below the
    /// attachments strip — when there's no media, the single message
    /// editor handles all text.
    var hasMedia: Bool {
        body.contains { $0.isMedia }
    }

    // MARK: - Block-list mutation helpers (Phase E.5.18)

    /// Inserts a media block while maintaining the editor's structural
    /// invariant `[firstParagraph, media*, trailingParagraph]` where
    /// **the leading and trailing paragraphs are distinct blocks** —
    /// the messageEditor binds to the first paragraph and the
    /// trailerEditor binds to the last; if they're the same block, both
    /// TextEditors render the same content (duplicate-text bug).
    ///
    /// Phase E.5.18b: the prior implementation only guaranteed a
    /// trailing paragraph. Inserting media into a body that contained a
    /// single typed paragraph would push that paragraph to the trailer
    /// position with NO leading paragraph remaining — causing both
    /// `message.get` and `trailerMessage.get` to return the same block.
    ///
    /// Algorithm:
    /// 1. Ensure body starts with a paragraph (the leading one). If the
    ///    body is empty or starts with media, prepend a fresh paragraph.
    /// 2. Ensure body ends with a paragraph that's NOT the same block as
    ///    the leading one. If the body has only one paragraph (which is
    ///    both first and last), append a fresh trailing paragraph.
    /// 3. Insert the media just before the trailing paragraph.
    ///
    /// Returns the trailing paragraph's id so the caller can move focus
    /// into it after inserting.
    @discardableResult
    func insertMedia(_ payload: MediaPayload, size: MediaBlockSize = .medium) -> UUID {
        let mediaBlock = TextBlock.media(payload, size: size)

        // Step 1 — ensure leading paragraph exists.
        if body.first?.isParagraph != true {
            body.insert(.paragraph(), at: 0)
        }
        let leadingId = body.first!.id

        // Step 2 — ensure trailing paragraph is distinct from leading.
        if body.last?.isParagraph != true || body.last!.id == leadingId {
            body.append(.paragraph())
        }
        let trailingId = body.last!.id

        // Step 3 — insert media just before the trailing paragraph.
        body.insert(mediaBlock, at: body.count - 1)
        return trailingId
    }

    /// Removes the block with the given id. If removing leaves the body
    /// empty, restores a single empty paragraph block so the editor
    /// keeps a cursor target. Adjacent paragraph blocks are intentionally
    /// NOT merged — the user can collapse them by hand if desired (matches
    /// how Apple Notes handles deletion of inline images).
    func removeBlock(id: UUID) {
        body.removeAll { $0.id == id }
        if body.isEmpty {
            body = [.paragraph()]
        }
    }

    /// Updates the size preset of a media block. No-op if the id refers
    /// to a paragraph block or doesn't exist.
    func resizeMediaBlock(id: UUID, to newSize: MediaBlockSize) {
        guard let i = body.firstIndex(where: { $0.id == id }) else { return }
        if case .media(let payload, _) = body[i].kind {
            body[i].kind = .media(payload, size: newSize)
        }
    }

    /// Updates a paragraph block's text (used by the editor's per-block
    /// `TextEditor` binding). No-op if the id refers to a media block.
    func updateParagraph(id: UUID, to text: AttributedString) {
        guard let i = body.firstIndex(where: { $0.id == id }) else { return }
        if case .paragraph = body[i].kind {
            body[i].kind = .paragraph(text)
        }
    }
}
