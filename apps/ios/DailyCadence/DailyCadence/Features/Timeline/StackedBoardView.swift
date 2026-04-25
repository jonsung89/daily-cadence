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

    @State private var expandedType: NoteType? = nil
    @Namespace private var stackNamespace

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
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
        VStack(spacing: 8) {
            ForEach(indices, id: \.self) { idx in
                let group = groups[idx]
                if group.type == expandedType {
                    ExpandedColumnSection(
                        group: group,
                        namespace: stackNamespace,
                        onCollapse: { toggle(group.type) }
                    )
                } else {
                    CollapsedStackCell(
                        group: group,
                        namespace: stackNamespace,
                        onTap: { toggle(group.type) }
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

    /// Up to 3 most-recent notes — the visible layers when collapsed.
    /// Stored newest-first; index 0 = top of stack.
    private var topNotes: [MockNote] {
        Array(group.notes.reversed().prefix(3))
    }

    private var hiddenCount: Int {
        max(0, group.notes.count - 3)
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
        let topOffset = CGFloat(max(0, topNotes.count - 1)) * 8

        return ZStack(alignment: .top) {
            ForEach(Array(topNotes.enumerated()), id: \.element.id) { index, note in
                // depth: how far behind the top card. 0 = oldest visible
                // layer (highest in y), count-1 = newest (lowest in y).
                let depth = topNotes.count - 1 - index
                KeepCard(note: note)
                    .fixedSize(horizontal: false, vertical: true)
                    .scaleEffect(1 - CGFloat(index) * 0.04)
                    .offset(y: CGFloat(depth) * 8)
                    .opacity(1 - CGFloat(index) * 0.16)
                    .zIndex(Double(topNotes.count - index))
                    .matchedGeometryEffect(id: note.id, in: namespace, properties: .position)
            }

            if hiddenCount > 0 {
                Text("+\(hiddenCount)")
                    .font(.DS.sans(size: 11, weight: .semibold))
                    .foregroundStyle(Color.DS.fg2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.DS.bg2))
                    .overlay(Capsule().stroke(Color.DS.border1, lineWidth: 1))
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    // Match the newest card's offset so the badge anchors
                    // to its corner, not the ZStack frame's corner.
                    .offset(y: topOffset)
                    .zIndex(Double(topNotes.count + 1))
            }
        }
        // Reserve breathing room below for the newest card's offset so
        // it doesn't visually overflow into the next column item.
        .padding(.bottom, topOffset)
    }
}

// MARK: - Expanded column section

/// A group rendered vertically inside its column. Cards stack
/// oldest-first (matches `group.notes` natural order); the "Collapse"
/// pill anchors at the bottom-right of the section, just below the
/// newest card.
private struct ExpandedColumnSection: View {
    let group: (type: NoteType, notes: [MockNote])
    let namespace: Namespace.ID
    let onCollapse: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(group.notes) { note in
                KeepCard(note: note)
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
