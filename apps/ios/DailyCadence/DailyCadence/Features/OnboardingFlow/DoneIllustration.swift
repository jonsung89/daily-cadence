import SwiftUI

/// Done page illustration. Plant in bloom (the sprout reaches its
/// flower) plus a small cluster of sparkles to suggest completion and
/// delight. Bookends the Welcome page's growing-plant motif: the
/// plant has grown.
struct DoneIllustration: View {
    var body: some View {
        let primary = ThemeStore.shared.primary.deep.color()

        ZStack {
            // Plant in bloom — the focal mark.
            PlantSprout(bloom: true)
                .stroke(
                    primary.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 110, height: 150)
                .offset(x: -10, y: 10)

            // Sparkle cluster — three sparkles at varied sizes around
            // the bloom, suggesting "you've finished, this is nice."
            SparkleMark()
                .stroke(
                    primary.opacity(0.50),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 22, height: 22)
                .offset(x: 70, y: -56)

            SparkleMark()
                .stroke(
                    primary.opacity(0.40),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 14, height: 14)
                .offset(x: 86, y: -22)

            SparkleMark()
                .stroke(
                    primary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 10, height: 10)
                .offset(x: 56, y: -82)

            // Subtle ground squiggle below the plant for grounding.
            LooseSquiggle()
                .stroke(
                    primary.opacity(0.18),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .frame(width: 90, height: 12)
                .offset(x: -10, y: 92)
        }
        .frame(width: 240, height: 220)
    }
}

#Preview("Light") {
    DoneIllustration()
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.DS.bg1)
}
