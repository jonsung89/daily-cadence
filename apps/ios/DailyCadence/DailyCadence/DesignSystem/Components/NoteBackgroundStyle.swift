import Foundation

/// The renderable form of a note's background — what `NoteCard` and
/// `KeepCard` actually consume.
///
/// Decoupled from `MockNote.Background` (which is the *storage* shape) so
/// the design-system layer doesn't import the model layer. View code reads
/// `note.resolvedBackgroundStyle` and forwards the result.
///
/// Cases:
/// - `.none` — fall back to the card's default surface (white in `NoteCard`,
///   type-tinted softColor in `KeepCard`)
/// - `.color(Swatch)` — fill with the swatch at 0.333 opacity over the
///   default surface (Phase D.1 behavior)
/// - `.image(data:opacity:)` — render the photo bytes scaled-to-fill the
///   card, clipped to the card's corner radius, at the chosen opacity. No
///   crop UI yet (D.2.2 deferred).
enum NoteBackgroundStyle: Equatable {
    case none
    case color(Swatch)
    case image(data: Data, opacity: Double)

    var hasCustomBackground: Bool {
        switch self {
        case .none:  return false
        case .color, .image: return true
        }
    }
}
