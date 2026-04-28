import SwiftUI

/// Wrapping flow layout — places children left-to-right, wrapping to a
/// new row when the next child would exceed the available width. Each
/// child sizes to its intrinsic width (unlike `LazyVGrid` with
/// `.flexible()` columns, which forces every cell to a fixed
/// fraction). Rows align to the chosen `alignment` so a final
/// short row can center / leading / trailing.
///
/// Reusable across surfaces that need a "tag cloud" arrangement —
/// note-type picker (Phase F.1.2.picker), future recipe-tag picker
/// (captured in PROGRESS.md TODO), filter-chip rows, etc.
struct FlowLayout: Layout {
    /// Horizontal gap between children within a row.
    var spacing: CGFloat = 12
    /// Vertical gap between wrapped rows.
    var rowSpacing: CGFloat = 12
    /// Per-row horizontal alignment. `.center` produces a balanced
    /// "spread" look that matches Jon's "evenly spread out" intent.
    var alignment: Alignment = .center

    enum Alignment {
        case leading, center, trailing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        let rows = computeRows(width: containerWidth, subviews: subviews)
        let totalHeight =
            rows.reduce(0) { $0 + $1.height }
            + CGFloat(max(0, rows.count - 1)) * rowSpacing
        return CGSize(width: containerWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = computeRows(width: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            let rowWidth =
                row.indices.reduce(CGFloat(0)) { acc, i in
                    acc + subviews[i].sizeThatFits(.unspecified).width
                }
                + CGFloat(max(0, row.indices.count - 1)) * spacing

            let xStart: CGFloat = {
                switch alignment {
                case .leading:  return bounds.minX
                case .center:   return bounds.minX + (bounds.width - rowWidth) / 2
                case .trailing: return bounds.maxX - rowWidth
                }
            }()

            var x = xStart
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row {
        var indices: [Int]
        var height: CGFloat
    }

    /// Greedily packs subviews into rows. A child wraps only if adding
    /// it (with leading spacing) would exceed `width`. Single oversize
    /// children still get their own row.
    private func computeRows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row(indices: [], height: 0)
        var currentWidth: CGFloat = 0

        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let withGap = size.width + (current.indices.isEmpty ? 0 : spacing)

            if currentWidth + withGap > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [i], height: size.height)
                currentWidth = size.width
            } else {
                current.indices.append(i)
                current.height = max(current.height, size.height)
                currentWidth += withGap
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
