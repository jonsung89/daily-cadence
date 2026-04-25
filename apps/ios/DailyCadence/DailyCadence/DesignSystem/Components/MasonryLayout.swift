import SwiftUI

/// Custom 2-column masonry layout for the Board's Free view (Phase E.4.5).
///
/// **Why a custom `Layout`.** The previous HStack-of-VStacks approach was
/// vulnerable to SwiftUI's flex-sizing: cards using `.frame(maxHeight: …)`
/// reported a flexible preferred size, and the column VStack — combined
/// with `.draggable` / `.dropDestination` interactions — would sometimes
/// allocate a card more vertical space than its content needed. The
/// background then coloured only the content portion, leaving visible
/// whitespace inside the card frame (the bug the user kept hitting).
///
/// `Layout` cuts that ambiguity off at the root: each subview is queried
/// for `sizeThatFits(.init(width: columnWidth, height: nil))`, which
/// returns the **intrinsic** height for the proposed column width, and
/// we place the subview at exactly that size. Cards can no longer be
/// inflated by the parent.
///
/// **Algorithm.** Shortest-column-first packing — each subview lands in
/// whichever column currently has the smallest accumulated height. With
/// only two columns it converges quickly to a balanced layout, even when
/// card heights vary wildly. The previous strict alternation (idx 0 →
/// left, idx 1 → right, …) is dropped — the user can hand-balance via
/// the Free view's drag-to-reorder when they want a specific arrangement.
///
/// `columns` and `spacing` are configurable; the rest of the app uses
/// 2 columns and 12pt to match the design system's outer gutter.
struct MasonryLayout: Layout {
    var columns: Int = 2
    var spacing: CGFloat = 12

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 0
        guard width > 0 else { return .zero }
        let result = pack(width: width, subviews: subviews)
        return CGSize(width: width, height: result.totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard bounds.width > 0 else { return }
        let columnWidth = computeColumnWidth(width: bounds.width)
        let result = pack(width: bounds.width, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            let size = subviews[index].sizeThatFits(
                ProposedViewSize(width: columnWidth, height: nil)
            )
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: size.height)
            )
        }
    }

    // MARK: - Pack

    private struct PackResult {
        let positions: [CGPoint]
        let totalHeight: CGFloat
    }

    private func pack(width: CGFloat, subviews: Subviews) -> PackResult {
        let columnWidth = computeColumnWidth(width: width)
        var columnHeights = Array(repeating: CGFloat(0), count: columns)
        var positions = [CGPoint]()
        positions.reserveCapacity(subviews.count)

        for subview in subviews {
            // Pick the shortest column. Ties resolve to the leftmost so
            // the very first subview always lands in column 0 — feels
            // natural and matches how Google Keep places the first card.
            var shortest = 0
            for i in 1..<columns where columnHeights[i] < columnHeights[shortest] {
                shortest = i
            }

            let size = subview.sizeThatFits(
                ProposedViewSize(width: columnWidth, height: nil)
            )
            let x = CGFloat(shortest) * (columnWidth + spacing)
            let y = columnHeights[shortest]
            positions.append(CGPoint(x: x, y: y))
            // Bump the column height by the subview's intrinsic height
            // plus a trailing spacing slot. We strip the final trailing
            // slot below when computing total height.
            columnHeights[shortest] = y + size.height + spacing
        }

        // Strip the trailing spacing from each non-empty column so we
        // don't report extra padding at the bottom of the grid.
        let totalHeight = columnHeights
            .map { $0 > 0 ? $0 - spacing : 0 }
            .max() ?? 0
        return PackResult(positions: positions, totalHeight: totalHeight)
    }

    private func computeColumnWidth(width: CGFloat) -> CGFloat {
        guard columns > 0 else { return width }
        let totalSpacing = CGFloat(columns - 1) * spacing
        return max(0, (width - totalSpacing) / CGFloat(columns))
    }
}
