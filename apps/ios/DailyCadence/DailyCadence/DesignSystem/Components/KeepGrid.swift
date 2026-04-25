import SwiftUI

/// A 2-column masonry grid for Google Keep-style cards.
///
/// Matches `.keep-grid` / `.keep-col` in `mobile.css`:
/// - Two equal-width columns, 8pt gap between and within columns
/// - Items alternate between columns (idx 0 → left, idx 1 → right, idx 2 → left, …)
///   which yields a naturally staggered masonry layout because card heights
///   vary by content kind
///
/// Alternation is deliberately simpler than a true shortest-column packer —
/// it keeps insertion order legible (new items go where you expect) and
/// matches the design system's JSX prototype, which pre-assigns items to
/// columns by eye.
struct KeepGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    @ViewBuilder let content: (Item) -> Content

    init(
        items: [Item],
        spacing: CGFloat = 8,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            column(indices: leftIndices)
            column(indices: rightIndices)
        }
    }

    private func column(indices: [Int]) -> some View {
        VStack(spacing: spacing) {
            ForEach(indices, id: \.self) { idx in
                content(items[idx])
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var leftIndices: [Int] {
        items.indices.filter { $0.isMultiple(of: 2) }
    }

    private var rightIndices: [Int] {
        items.indices.filter { !$0.isMultiple(of: 2) }
    }
}

// MARK: - Previews

#Preview("Light") {
    ScrollView {
        KeepGrid(items: MockNotes.today) { note in
            KeepCard(note: note)
        }
        .padding(16)
    }
    .background(Color.DS.bg1)
}

#Preview("Dark") {
    ScrollView {
        KeepGrid(items: MockNotes.today) { note in
            KeepCard(note: note)
        }
        .padding(16)
    }
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}
