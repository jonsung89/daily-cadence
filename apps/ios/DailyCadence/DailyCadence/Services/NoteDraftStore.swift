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

    /// Rich-text message body — Phase E.2 `AttributedString` with per-run
    /// font + foregroundColor attributes.
    var message: AttributedString = AttributedString("")

    /// Selection state for the message's `TextEditor`.
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

    init() {}

    /// True when the user has typed nothing and made no styling choices.
    /// Used to skip the draft-restore branch on a totally fresh open so the
    /// editor still autofocuses cleanly.
    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        message.characters.isEmpty &&
        background == nil &&
        titleStyle == nil &&
        messageFontId == nil &&
        messageColorId == nil
    }

    /// Reset the draft to its pristine state — called from Save (the note
    /// was committed to the timeline) and Cancel (intentional discard).
    func clear() {
        title = ""
        message = AttributedString("")
        messageSelection = AttributedTextSelection()
        messageFontId = nil
        messageColorId = nil
        messageSize = 16
        titleStyle = nil
        selectedType = .mood
        background = nil
    }
}
