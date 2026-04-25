import Foundation

/// Sub-mode of the Today screen's `Board` view — how cards are organized.
///
/// Exposed via a 3-position segmented control that appears only when
/// `TimelineViewMode == .board`. Inspired by macOS desktop stacks: the
/// user can arrange freely as **Cards** (the default — drag-to-reorder
/// 2-column masonry), pile notes by type (**Stack**), or see them as
/// flat sections by type (**Group**).
///
/// **Order in `allCases`** is the visual order in the segmented toggle —
/// `.cards` is first (default + most-used), then `.stacked`, then
/// `.grouped`.
///
/// **Naming history.** The `.cards` case was originally `.free` (Phase F.1);
/// renamed in Phase E.5.1 to "Cards" since "Free" didn't communicate what
/// the view is.
enum BoardLayoutMode: Hashable, CaseIterable, Identifiable {
    /// Cards rendered in a 2-column masonry with drag-to-reorder. The
    /// default arrangement.
    case cards
    /// Cards group by `NoteType` and render as overlapping stacks. Tap to
    /// expand a stack inline.
    case stacked
    /// Cards group by `NoteType` into flat sections with type headers.
    /// All cards visible at once.
    case grouped

    var id: Self { self }

    var title: String {
        switch self {
        case .cards:   return "Cards"
        case .stacked: return "Stack"
        case .grouped: return "Group"
        }
    }

    var systemImage: String {
        switch self {
        case .cards:   return "square.grid.2x2"
        case .stacked: return "square.stack.3d.up"
        case .grouped: return "rectangle.grid.2x2.fill"
        }
    }
}
