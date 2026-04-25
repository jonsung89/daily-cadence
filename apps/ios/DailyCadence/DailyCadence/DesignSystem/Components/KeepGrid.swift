import SwiftUI

/// A 2-column masonry grid for Google Keep-style cards.
///
/// Backed by `MasonryLayout` (Phase E.4.5) — a custom `Layout` that
/// shortest-column-first-packs each subview at its **intrinsic** height
/// for the proposed column width. Replaces the prior HStack-of-VStacks
/// approach, which was vulnerable to SwiftUI's flex-sizing inflating
/// short cards when the parent column had spare height (the
/// "card-with-whitespace" bug).
struct KeepGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    @ViewBuilder let content: (Item) -> Content

    init(
        items: [Item],
        spacing: CGFloat = 12,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        MasonryLayout(columns: 2, spacing: spacing) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

// MARK: - Previews

#Preview("Light") {
    ScrollView {
        KeepGrid(items: MockNotes.today) { note in
            KeepCard(note: note)
        }
        .padding(12)
    }
    .background(Color.DS.bg1)
}

#Preview("Dark") {
    ScrollView {
        KeepGrid(items: MockNotes.today) { note in
            KeepCard(note: note)
        }
        .padding(12)
    }
    .background(Color.DS.bg1)
    .preferredColorScheme(.dark)
}
