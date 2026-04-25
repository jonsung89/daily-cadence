import Foundation

/// Sub-mode of the Today screen's `Board` view — how cards are organized.
///
/// Exposed via a 3-position segmented control that appears only when
/// `TimelineViewMode == .board`. Inspired by macOS desktop stacks: the user
/// can pile notes by type (Stacked), see them as flat sections by type
/// (Grouped), or arrange freely (Free).
///
/// Phases:
/// - **F.1 (current)** — `.grouped` and `.free` are real renderings;
///   `.stacked` is stubbed to render as Grouped until F.2 builds the
///   overlapping-cards visual + tap-to-expand animation.
/// - **F.2** — real stacked mode (overlapping cards + expand/collapse).
/// - **F.3** — drag-to-reorder in `.free` mode with persistence.
enum BoardLayoutMode: Hashable, CaseIterable, Identifiable {
    /// Cards group by `NoteType` and render as overlapping stacks. Tap to
    /// expand a stack inline. *F.1: stub — renders as Grouped.*
    case stacked
    /// Cards group by `NoteType` into flat sections with type headers.
    /// All cards visible at once.
    case grouped
    /// Cards rendered in a 2-column masonry exactly as they're stored —
    /// the existing Board layout. F.3 will add drag-to-reorder.
    case free

    var id: Self { self }

    var title: String {
        switch self {
        case .stacked: return "Stack"
        case .grouped: return "Group"
        case .free:    return "Free"
        }
    }

    var systemImage: String {
        switch self {
        case .stacked: return "square.stack.3d.up"
        case .grouped: return "rectangle.grid.2x2.fill"
        case .free:    return "square.grid.2x2"
        }
    }
}
