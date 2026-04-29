import SwiftUI

/// Hand-drawn-feeling ornamentation for the Welcome page. Composes
/// the shared journal motifs (`SunMark`, `PlantSprout`,
/// `LooseSquiggle`) into a balanced vignette: sun in upper-right, plant
/// sprout in lower-left, soft squiggle through the middle, accent dot
/// for visual punctuation. Theme-tinted via `ThemeStore.shared.primary`
/// so the illustration drifts with the user's chosen color.
///
/// Style + composition rules captured in
/// `feedback_journal_illustration_style.md` (memory). Reuse
/// `DesignSystem/Components/JournalShapes.swift` for new surfaces.
struct WelcomeIllustration: View {
    var body: some View {
        let primary = ThemeStore.shared.primary.deep.color()

        ZStack {
            SunMark(rayCount: 7)
                .stroke(
                    primary.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 58, height: 58)
                .offset(x: 78, y: -52)

            LooseSquiggle()
                .stroke(
                    primary.opacity(0.18),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .frame(width: 110, height: 18)
                .offset(x: 30, y: 5)

            PlantSprout()
                .stroke(
                    primary.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 78, height: 110)
                .offset(x: -68, y: 16)

            Circle()
                .fill(primary.opacity(0.35))
                .frame(width: 4, height: 4)
                .offset(x: 90, y: 60)
        }
        .frame(width: 240, height: 200)
    }
}

#Preview("Light") {
    WelcomeIllustration()
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.DS.bg1)
}

#Preview("Dark") {
    WelcomeIllustration()
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.DS.bg1)
        .preferredColorScheme(.dark)
}
