import SwiftUI

/// Sign-in illustration. Smaller and more horizontal than the
/// onboarding heroes since the wordmark is the page's focal point;
/// this sits in the empty space between tagline and sign-in buttons
/// to establish the journal-pen visual language at first contact.
///
/// Uses the default theme (`Color.DS.sage`) since nothing's been
/// picked yet, but reads through `ThemeStore` so a returning user
/// who's already chosen a theme still sees their color.
struct SignInIllustration: View {
    var body: some View {
        let primary = ThemeStore.shared.primary.deep.color()

        ZStack {
            // Sun on the right, smaller than Welcome.
            SunMark(rayCount: 6)
                .stroke(
                    primary.opacity(0.40),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 42, height: 42)
                .offset(x: 70, y: -8)

            // Plant on the left, balancing the sun.
            PlantSprout()
                .stroke(
                    primary.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 56, height: 80)
                .offset(x: -64, y: 14)

            // Faint squiggle ties them together horizontally.
            LooseSquiggle()
                .stroke(
                    primary.opacity(0.16),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                )
                .frame(width: 70, height: 12)
                .offset(x: 0, y: 28)
        }
        .frame(width: 200, height: 120)
    }
}

#Preview("Light") {
    SignInIllustration()
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.DS.bg1)
}
