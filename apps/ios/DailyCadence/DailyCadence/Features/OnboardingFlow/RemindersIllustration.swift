import SwiftUI

/// Reminders page illustration. A crescent moon with a small star
/// cluster around it: calm, end-of-day, "we'll nudge you gently"
/// feel. Distinct from Welcome's sun motif and Done's bloomed plant
/// so each onboarding moment has its own emotional texture.
///
/// The earlier draft used a procedurally-drawn bell + motion arcs.
/// It came out clumsy (bells are unforgiving in stroke-only
/// rendering) and the metaphor felt aggressive for "gentle reminder."
/// Replaced with the moon + stars vocabulary captured in the journal
/// illustration memory.
struct RemindersIllustration: View {
    var body: some View {
        let primary = ThemeStore.shared.primary.deep.color()

        ZStack {
            // Crescent moon — focal mark, slightly off-center.
            CrescentMoon(phase: 0.6)
                .stroke(
                    primary.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 86, height: 86)
                .offset(x: -18, y: 0)

            // Star cluster scattered around the moon — three sparkles
            // at varied sizes and opacities so the eye reads them as
            // distance + ambience, not formation.
            SparkleMark()
                .stroke(
                    primary.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 22, height: 22)
                .offset(x: 64, y: -56)

            SparkleMark()
                .stroke(
                    primary.opacity(0.40),
                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 14, height: 14)
                .offset(x: 88, y: -8)

            SparkleMark()
                .stroke(
                    primary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 10, height: 10)
                .offset(x: 56, y: 52)

            // Punctuating dots — small, off the cluster, give the
            // composition negative-space rhythm.
            Circle()
                .fill(primary.opacity(0.35))
                .frame(width: 4, height: 4)
                .offset(x: -78, y: -54)

            Circle()
                .fill(primary.opacity(0.30))
                .frame(width: 3, height: 3)
                .offset(x: -60, y: 62)
        }
        .frame(width: 240, height: 200)
    }
}

#Preview("Light") {
    RemindersIllustration()
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.DS.bg1)
}

#Preview("Dark") {
    RemindersIllustration()
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.DS.bg1)
        .preferredColorScheme(.dark)
}
