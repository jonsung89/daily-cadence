import SwiftUI

/// Layout primitive shared by every onboarding page.
///
/// Each page composes its content by passing closures into this view —
/// guarantees a consistent rhythm: progress dots + skip up top, hero
/// glyph centered above title + body, control area below, primary
/// (and optional secondary) CTA at the bottom. Background is `bg1`
/// with a soft tint of the user's currently-selected theme `softColor`,
/// so the screen reflects their picks live as they make them.
///
/// The shared chrome doesn't know how many pages there are or what
/// "Next" means — `OnboardingFlow` owns the state machine and passes
/// in `onPrimary` / `onSkip` closures.
struct OnboardingChrome<Hero: View, Control: View>: View {
    let pageIndex: Int
    let pageCount: Int
    let canSkip: Bool
    let title: String
    let bodyText: String?
    let primaryLabel: String
    let secondaryLabel: String?
    let isPrimaryEnabled: Bool
    let onPrimary: () -> Void
    let onSecondary: (() -> Void)?
    let onSkip: (() -> Void)?
    @ViewBuilder let hero: () -> Hero
    @ViewBuilder let control: () -> Control

    init(
        pageIndex: Int,
        pageCount: Int,
        canSkip: Bool = true,
        title: String,
        body: String? = nil,
        primaryLabel: String,
        secondaryLabel: String? = nil,
        isPrimaryEnabled: Bool = true,
        onPrimary: @escaping () -> Void,
        onSecondary: (() -> Void)? = nil,
        onSkip: (() -> Void)? = nil,
        @ViewBuilder hero: @escaping () -> Hero,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.pageIndex = pageIndex
        self.pageCount = pageCount
        self.canSkip = canSkip
        self.title = title
        self.bodyText = body
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.isPrimaryEnabled = isPrimaryEnabled
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        self.onSkip = onSkip
        self.hero = hero
        self.control = control
    }

    var body: some View {
        // ScrollView fills the entire screen. TopBar and footer are
        // overlays anchored to the top and bottom — content scrolls
        // BEHIND them with a soft gradient fade at each edge. That's
        // what makes the page feel like one continuous visual surface
        // instead of a sandwich (top bar / scroll area / bottom bar
        // sitting on a static background).
        ScrollView {
            VStack(spacing: Spacing.s5) {
                // Top spacer puts the hero below the topBar's space
                // initially, but the area is part of the scroll content
                // so it can rise behind the topBar with the soft fade
                // when the user scrolls up.
                Color.clear.frame(height: topBarReservedHeight)

                hero()
                    .frame(maxWidth: .infinity)

                VStack(spacing: Spacing.s3) {
                    Text(title)
                        .font(.DS.serif(size: 32, weight: .medium))
                        .foregroundStyle(Color.DS.ink)
                        .multilineTextAlignment(.center)

                    if let bodyText {
                        Text(bodyText)
                            .font(.DS.body)
                            .foregroundStyle(Color.DS.fg2)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Spacing.s5)

                control()
                    .padding(.horizontal, Spacing.s5)
                    .padding(.top, Spacing.s3)

                // Bottom spacer reserves room for the footer chrome.
                Color.clear.frame(height: footerReservedHeight)
            }
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tintedBackground)
        .overlay(alignment: .top) { topBarLayer }
        .overlay(alignment: .bottom) { footerLayer }
        .overlay(alignment: .topLeading) { ambientTopLeading }
        .overlay(alignment: .topTrailing) { ambientTopTrailing }
        .overlay(alignment: .bottomLeading) { ambientBottomLeading }
        .overlay(alignment: .bottomTrailing) { ambientBottomTrailing }
    }

    /// Reserved height for the topBar zone (progress dots + skip + the
    /// padding around them + the device's top safe area). Content
    /// scrolls under it; the soft scroll-edge fade hides the rise.
    private var topBarReservedHeight: CGFloat { 56 }

    /// Reserved height for the footer zone (primary CTA + secondary +
    /// padding + the device's bottom safe area).
    private var footerReservedHeight: CGFloat { 130 }

    private var topBarLayer: some View {
        topBar
            .padding(.horizontal, Spacing.s5)
            .padding(.top, Spacing.s3)
            .padding(.bottom, Spacing.s2)
    }

    private var footerLayer: some View {
        footer
            .padding(.horizontal, Spacing.s5)
            .padding(.top, Spacing.s3)
            .padding(.bottom, Spacing.s5)
    }

    /// Ambient ornaments tucked into the screen's four corners so every
    /// onboarding page reads as part of the same hand-drawn world.
    /// Positioned with generous padding so they never overlap content
    /// or interactive elements (`allowsHitTesting(false)` belt-and-
    /// suspenders against a stray drag intercepting taps near a button).
    /// Color follows the user's current theme via `ThemeStore`.
    private var ambientColor: Color {
        ThemeStore.shared.primary.deep.color()
    }

    private var ambientTopLeading: some View {
        LooseSquiggle()
            .stroke(
                ambientColor.opacity(0.30),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
            )
            .frame(width: 80, height: 14)
            .padding(.leading, 24)
            .padding(.top, 80)
            .allowsHitTesting(false)
    }

    private var ambientTopTrailing: some View {
        SparkleMark()
            .stroke(
                ambientColor.opacity(0.45),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 18, height: 18)
            .padding(.trailing, 30)
            .padding(.top, 90)
            .allowsHitTesting(false)
    }

    private var ambientBottomLeading: some View {
        SparkleMark()
            .stroke(
                ambientColor.opacity(0.38),
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 14, height: 14)
            .padding(.leading, 28)
            .padding(.bottom, 200)
            .allowsHitTesting(false)
    }

    private var ambientBottomTrailing: some View {
        Circle()
            .fill(ambientColor.opacity(0.40))
            .frame(width: 5, height: 5)
            .padding(.trailing, 44)
            .padding(.bottom, 220)
            .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            ProgressDots(current: pageIndex, total: pageCount)
            Spacer()
            if canSkip, let onSkip {
                Button("Skip") {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onSkip()
                }
                .font(.DS.body)
                .foregroundStyle(Color.DS.fg2)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: Spacing.s3) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                onPrimary()
            } label: {
                Text(primaryLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.DS.fgOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.DS.sage)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .disabled(!isPrimaryEnabled)
            .opacity(isPrimaryEnabled ? 1.0 : 0.4)

            if let secondaryLabel, let onSecondary {
                Button(secondaryLabel) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onSecondary()
                }
                .font(.DS.body)
                .foregroundStyle(Color.DS.fg2)
            }
        }
    }

    /// Reads `ThemeStore.shared.primary.softColor` — when the user
    /// changes their theme on page 2, every page's background gets a
    /// gentle wash of the new color. The gradient is light enough
    /// (12% top, 0% bottom) that it doesn't fight the page content.
    private var tintedBackground: some View {
        let soft = ThemeStore.shared.primary.soft.color()
        return LinearGradient(
            stops: [
                .init(color: soft.opacity(0.18), location: 0.0),
                .init(color: Color.DS.bg1, location: 0.55),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// Pill-style progress indicator. Active dot widens slightly so
/// progress is legible without a numeric counter.
private struct ProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.DS.sage : Color.DS.border1)
                    .frame(width: index == current ? 22 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
    }
}
