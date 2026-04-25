import SwiftUI

/// The floating action button — primary "create new note" entry point on the
/// Daily Timeline screen.
///
/// Matches `.fab` in `mobile.css`:
/// - 56pt diameter circle
/// - Sage (primary-theme) fill, white foreground
/// - Plus icon (24pt, semibold)
///
/// Shadow: uses the neutral `dsShadow(.level2)` instead of the CSS's
/// theme-tinted `0 12px 24px rgba(sage, .35)`. Tinted shadows looked heavy
/// against the cream background and bled visually into the surrounding —
/// neutral warm-ink shadow ages better and doesn't compound when the user
/// picks a saturated theme (Coral, Bold-magenta, etc.).
///
/// Anchor at 16pt from bottom-right of the screen, 104pt up to clear the
/// 88pt tab bar + 16pt breathing room (anchoring is the caller's job — this
/// view is just the button).
struct FAB: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    init(
        systemImage: String = "plus",
        accessibilityLabel: String = "Add a note",
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(Color.DS.sage)
                )
                .dsShadow(.level2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("Light") {
    ZStack(alignment: .bottomTrailing) {
        Color.DS.bg1.ignoresSafeArea()
        FAB { }
            .padding(.trailing, 20)
            .padding(.bottom, 104)
    }
}

#Preview("Dark") {
    ZStack(alignment: .bottomTrailing) {
        Color.DS.bg1.ignoresSafeArea()
        FAB { }
            .padding(.trailing, 20)
            .padding(.bottom, 104)
    }
    .preferredColorScheme(.dark)
}

#Preview("Custom icon") {
    ZStack(alignment: .bottomTrailing) {
        Color.DS.bg1.ignoresSafeArea()
        FAB(systemImage: "pencil", accessibilityLabel: "Edit") { }
            .padding(.trailing, 20)
            .padding(.bottom, 104)
    }
}
