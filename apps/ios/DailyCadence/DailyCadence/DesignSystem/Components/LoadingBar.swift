import SwiftUI

/// Thin animated indeterminate progress bar.
///
/// Phase F.0.3 — replaces the per-content `.redacted(.placeholder)`
/// skeleton on the Today screen. The skeleton flashed in and out on
/// every short day-switch fetch, which felt noisy; a 2pt sage bar at
/// the top of the screen is the modern Safari / Mail equivalent — a
/// quiet "something's happening" signal that doesn't reorganize the
/// layout when it appears or disappears.
///
/// Built as a custom SwiftUI animation rather than `ProgressView` so
/// we get a clean indeterminate slide that uses our brand sage color
/// at the design-system tint. The track is sage at 0.15 opacity; a
/// segment of full sage slides across.
///
/// Sized at 2pt by default. Caller controls vertical positioning —
/// typically pinned via `.overlay(alignment: .top)` on the timeline.
struct LoadingBar: View {
    /// 0..1 — drives the sliding indicator. Animated externally (we
    /// flip between 0 and 1 with a `repeatForever` linear animation
    /// in `.onAppear`).
    @State private var phase: CGFloat = 0

    /// Fraction of the bar's width occupied by the moving indicator.
    /// A narrow segment reads as "indeterminate progress"; a wide one
    /// reads as "almost done" — the former matches our intent.
    private let indicatorWidth: CGFloat = 0.35

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = proxy.size.width
            let segWidth = trackWidth * indicatorWidth
            // Travel from off-screen left → off-screen right so the
            // indicator slides through cleanly without bouncing.
            let travel = trackWidth + segWidth
            ZStack(alignment: .leading) {
                Color.DS.sage.opacity(0.15)
                Color.DS.sage
                    .frame(width: segWidth)
                    .offset(x: phase * travel - segWidth)
            }
            .clipped()
        }
        .frame(height: 2)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

#Preview {
    VStack(spacing: 32) {
        LoadingBar()
        LoadingBar()
            .preferredColorScheme(.dark)
    }
    .padding()
    .background(Color.DS.bg1)
}
