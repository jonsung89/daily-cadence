import SwiftUI

/// The Stacked layout for the Today screen's Board view (Phase F.2).
///
/// Each note type renders as a "stack of cards" — the most recent note
/// sits at the bottom of the visual stack with up to 2 older cards
/// peeking *above* it (each progressively smaller and more faded). Older
/// cards peek above (not below) the newest card so the stack still reads
/// as a stack even when the top card is taller than the ones beneath.
/// Stacks are arranged in a **2-column masonry** (matching Free mode's
/// column count + alternation rule): index 0 → left col, 1 → right col,
/// 2 → left col, …
///
/// Tapping a stack expands it **vertically inside its own column**: every
/// card in the group renders top-to-bottom (oldest → newest) starting at
/// the slot the stack occupied. The other column is untouched, so cells
/// never jump sideways. At most one stack is expanded at a time —
/// switching auto-collapses the previous (uses `matchedGeometryEffect`
/// with `properties: .position` so cards smoothly slide between stack and
/// expanded positions while each side keeps its own natural size).
///
/// Collapsed stacks have no header chrome — the top card already carries
/// the type's pigment dot + uppercase label, so a duplicate header would
/// be redundant.
struct StackedBoardView: View {
    let groups: [(type: NoteType, notes: [MockNote])]
    /// Forwarded to each `KeepCard`'s `.contextMenu` Delete action
    /// (Phase E.5.15). Optional so previews don't have to wire it.
    var onRequestDelete: ((UUID) -> Void)? = nil
    /// Phase F.1.0 — forwarded to each `KeepCard`'s `onTap` callback,
    /// which fires when the user taps a text card to view+edit. The
    /// caller filters non-text content to nil so non-text cards
    /// remain non-tappable.
    var onRequestEdit: ((UUID) -> Void)? = nil
    /// Phase F.1.1b'.zoom — forwarded to each card so media taps route
    /// through the parent's namespace + navigation push. Optional so
    /// previews work without it.
    var mediaTapHandler: MediaTapHandler? = nil

    @State private var expandedType: NoteType? = nil
    @Namespace private var stackNamespace

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(at: leftIndices)
            column(at: rightIndices)
        }
    }

    /// Indices of groups assigned to the left column (0, 2, 4, …) —
    /// matches `KeepGrid`'s alternation rule so Stacked and Free modes
    /// place cards in the same columns.
    private var leftIndices: [Int] {
        groups.indices.filter { $0.isMultiple(of: 2) }
    }

    private var rightIndices: [Int] {
        groups.indices.filter { !$0.isMultiple(of: 2) }
    }

    private func column(at indices: [Int]) -> some View {
        VStack(spacing: 12) {
            ForEach(indices, id: \.self) { idx in
                let group = groups[idx]
                if group.type == expandedType {
                    ExpandedColumnSection(
                        group: group,
                        namespace: stackNamespace,
                        onCollapse: { toggle(group.type) },
                        onRequestDelete: onRequestDelete,
                        onRequestEdit: onRequestEdit,
                        mediaTapHandler: mediaTapHandler
                    )
                } else {
                    CollapsedStackCell(
                        group: group,
                        namespace: stackNamespace,
                        onTap: { toggle(group.type) },
                        onRequestDelete: onRequestDelete,
                        onRequestEdit: onRequestEdit,
                        mediaTapHandler: mediaTapHandler
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func toggle(_ type: NoteType) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            expandedType = expandedType == type ? nil : type
        }
    }
}

// MARK: - Collapsed stack

/// A single group's collapsed cell — a fan of overlapping cards. No
/// header: the top card carries the type's label.
private struct CollapsedStackCell: View {
    let group: (type: NoteType, notes: [MockNote])
    let namespace: Namespace.ID
    let onTap: () -> Void
    var onRequestDelete: ((UUID) -> Void)? = nil
    var onRequestEdit: ((UUID) -> Void)? = nil
    var mediaTapHandler: MediaTapHandler? = nil

    /// Up to 3 most-recent notes — the visible layers when collapsed.
    /// Stored newest-first; index 0 = top of stack.
    private var topNotes: [MockNote] {
        Array(group.notes.reversed().prefix(3))
    }

    /// Total cards in the group. Drives the upper-right count badge
    /// (Phase E.5.23). Only shown when > 1 — single-card stacks read
    /// as plain cards already.
    private var totalCount: Int {
        group.notes.count
    }

    @ViewBuilder
    var body: some View {
        // A single-card "stack" has nothing to expand into — render the
        // fan without a tap handler so it doesn't pretend to be
        // interactive.
        if topNotes.count > 1 {
            Button(action: onTap) { stackFan }
                .buttonStyle(.plain)
        } else {
            stackFan
        }
    }

    private var stackFan: some View {
        // Newest card sits at the BOTTOM of the visual stack so the older
        // layers peek out *above* it. Peeking-above stays visible regardless
        // of whether the top card is taller than the cards beneath — peeking
        // *below* would disappear behind a tall top card and the stack would
        // look like a single card.
        //
        // **Phase E.5.27** — two coordinated changes:
        //
        // 1. `.padding(.top, depth × peek)` instead of `.offset(y: depth × 8)
        //    + .padding(.bottom, topOffset)`. The previous form used a
        //    visual-only offset that didn't participate in layout, so the
        //    ZStack's reported frame ended at `max(card heights)` while the
        //    newest card actually drew lower than that — and the cell
        //    tacked on a `.padding(.bottom, ...)` to compensate. That
        //    layout/visual mismatch is what `matchedGeometryEffect`
        //    reads, so when one stack expanded the spring animation
        //    propagated the warped frame into the opposite column and
        //    cards over there shifted. Padding-top is layout-affecting:
        //    the ZStack's frame now equals the newest card's true
        //    visual bottom, anchors are accurate, and the cross-column
        //    glitch goes away.
        //
        // 2. `peek` reduced from 8pt to 4pt per layer — the strip above
        //    the newest's "header" was `(count − 1) × 8 = 16pt` for a
        //    3-card stack and read as a visible gap before the newest's
        //    content. At 4pt the strip drops to 4-8pt and reads as a
        //    layered hint rather than a chunky gap. Older cards still
        //    visibly peek; the rhythm is preserved.
        let peek: CGFloat = 4
        return ZStack(alignment: .top) {
            ForEach(Array(topNotes.enumerated()), id: \.element.id) { index, note in
                // depth: how far behind the top card. 0 = oldest visible
                // layer (highest in y), count-1 = newest (lowest in y).
                let depth = topNotes.count - 1 - index
                KeepCard(
                    note: note,
                    onRequestDelete: onRequestDelete.map { cb in { cb($0.id) } },
                    onTap: onRequestEdit.map { cb in { cb(note.id) } },
                    mediaTapHandler: mediaTapHandler
                )
                    .fixedSize(horizontal: false, vertical: true)
                    .scaleEffect(1 - CGFloat(index) * 0.04)
                    .padding(.top, CGFloat(depth) * peek)
                    .opacity(1 - CGFloat(index) * 0.16)
                    .zIndex(Double(topNotes.count - index))
                    .matchedGeometryEffect(id: note.id, in: namespace, properties: .position)
            }

        }
        .overlay(alignment: .topTrailing) {
            // Phase E.5.23 — total-count badge in the upper-right corner
            // when the stack has more than one card. Replaces the
            // previous lower-right "+N hidden" badge with a single
            // unambiguous count (Apple Notes / Photos folder pattern).
            // Rendered as an overlay so it doesn't advertise an infinite
            // vertical size back to the parent VStack column.
            if totalCount > 1 {
                Text("\(totalCount)")
                    .font(.DS.sans(size: 11, weight: .semibold))
                    .foregroundStyle(Color.DS.ink.opacity(0.85))
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.DS.ink.opacity(0.12), lineWidth: 0.5)
                    )
                    .padding(8)
                    .zIndex(Double(topNotes.count + 1))
            }
        }
    }
}

// MARK: - Expanded column section

/// A group rendered vertically inside its column. Cards stack
/// oldest-first (matches `group.notes` natural order); the "Collapse"
/// pill anchors at the bottom-right of the section, just below the
/// newest card.
///
/// **Double-tap shortcut** (Phase E.5.9) — tapping anywhere in the
/// section twice quickly collapses the stack. The `.contentShape`
/// makes gaps between cards part of the tappable surface so the
/// shortcut works on the section "background" as well as on cards.
/// Single taps on inner views (e.g., a media card opening the
/// fullscreen viewer) still pass through; the system briefly defers
/// them to disambiguate from a double-tap (standard Apple pattern).
private struct ExpandedColumnSection: View {
    let group: (type: NoteType, notes: [MockNote])
    let namespace: Namespace.ID
    let onCollapse: () -> Void
    var onRequestDelete: ((UUID) -> Void)? = nil
    var onRequestEdit: ((UUID) -> Void)? = nil
    var mediaTapHandler: MediaTapHandler? = nil

    var body: some View {
        VStack(spacing: 8) {
            ForEach(group.notes) { note in
                KeepCard(
                    note: note,
                    onRequestDelete: onRequestDelete.map { cb in { cb($0.id) } },
                    onTap: onRequestEdit.map { cb in { cb(note.id) } },
                    mediaTapHandler: mediaTapHandler
                )
                    // `fixedSize(vertical: true)` forces the card to use
                    // its intrinsic height regardless of any frame
                    // propagated by `matchedGeometryEffect`. Without it,
                    // the front-most card in the stack passes its
                    // ZStack-clamped frame to its expanded twin and the
                    // text truncates to a single line.
                    .fixedSize(horizontal: false, vertical: true)
                    .matchedGeometryEffect(id: note.id, in: namespace, properties: .position)
            }
            HStack {
                Spacer(minLength: 0)
                Button(action: onCollapse) {
                    Label("Collapse", systemImage: "chevron.up")
                        .labelStyle(.titleAndIcon)
                        .font(.DS.sans(size: 11, weight: .semibold))
                        .foregroundStyle(Color.DS.fg2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.DS.bg2))
                        .overlay(Capsule().stroke(Color.DS.border1, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onCollapse() }
    }
}

// MARK: - Previews

#Preview("Stacked, light") {
    ScrollView {
        StackedBoardView(
            groups: groupsForPreview()
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    .background(Color.DS.bg1)
}

#Preview("Stacked, dark") {
    ScrollView {
        StackedBoardView(
            groups: groupsForPreview()
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}

private func groupsForPreview() -> [(type: NoteType, notes: [MockNote])] {
    let byType = Dictionary(grouping: MockNotes.today, by: \.type)
    return NoteType.allCases.compactMap { type in
        guard let notes = byType[type], !notes.isEmpty else { return nil }
        return (type, notes)
    }
}
