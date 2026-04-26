import SwiftUI

/// Small pin toggle that sits in the top-trailing corner of a note card.
/// Tap-to-toggle (Phase E.5.15 — Google Keep / Apple Notes pattern). Shows
/// `pin` (outline) when unpinned and `pin.fill` (filled, honey-yellow) when
/// pinned, matching Apple's universal "this is pinned" semantic.
///
/// **Why honey, not `type.color`.** Using the note's type pigment for the
/// pinned state would conflict perceptually with the type indicator
/// itself — a Workout note already shows a clay-orange dot + label, and
/// a pinned-orange pin next to it would muddle "is that a type cue or a
/// pin cue?" Honey is invariant across the design system (the only
/// non-light/dark-flipping token) so the pin reads the same regardless
/// of card background tint or theme.
///
/// **Hit area.** The 13pt SF Symbol sits inside a 32pt frame so the tap
/// target meets Apple HIG's 44pt minimum when combined with the card's
/// existing edge padding. `.contentShape(Rectangle())` makes the empty
/// padding tappable.
struct PinButton: View {
    let isPinned: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isPinned ? Color.DS.honey : Color.DS.fg2.opacity(0.45))
                .rotationEffect(.degrees(isPinned ? 0 : -30))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPinned ? "Unpin" : "Pin")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("States") {
    HStack(spacing: 24) {
        PinButton(isPinned: false, onToggle: {})
        PinButton(isPinned: true, onToggle: {})
    }
    .padding(40)
    .background(Color.DS.bg2)
}

#Preview("Dark") {
    HStack(spacing: 24) {
        PinButton(isPinned: false, onToggle: {})
        PinButton(isPinned: true, onToggle: {})
    }
    .padding(40)
    .background(Color.DS.bg2)
    .preferredColorScheme(.dark)
}
