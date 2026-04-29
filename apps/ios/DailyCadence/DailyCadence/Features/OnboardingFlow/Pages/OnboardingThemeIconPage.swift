import SwiftUI
import UIKit

/// Single page that picks both theme color AND app icon at once. They
/// share an underlying palette (8 entries, same ids), so picking
/// "Blush" sets `ThemeStore.primary = blush` AND triggers
/// `setAlternateIconName("BlushPink")`. The Settings-side pickers stay
/// independent for users who want them different later.
struct OnboardingThemeIconPage: View {
    let pageIndex: Int
    let pageCount: Int
    let onContinue: () -> Void
    let onSkip: () -> Void

    private let palette = PrimaryPaletteRepository.shared

    var body: some View {
        // Read ThemeStore.shared.primary inside `body` so this page
        // observes the live theme and the preview + selection ring
        // update the moment the user taps a swatch.
        let current = ThemeStore.shared.primary

        return OnboardingChrome(
            pageIndex: pageIndex,
            pageCount: pageCount,
            title: "Pick your color",
            body: "We'll match your home-screen icon to it. Change either separately in Settings.",
            primaryLabel: "Continue",
            onPrimary: onContinue,
            onSkip: onSkip
        ) {
            iconHero(for: current)
        } control: {
            swatchGrid(current: current)
        }
    }

    /// Live preview — shows the matching app-icon tile, not the
    /// abstract trio dots, because users associate this choice with
    /// "what my home screen will look like."
    private func iconHero(for current: PrimarySwatch) -> some View {
        let choice = AppIconChoice.from(themeId: current.id) ?? .sage
        return VStack(spacing: Spacing.s2) {
            ThemeIconPreview(choice: choice, size: 110)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
            Text(current.name)
                .font(.DS.body.weight(.medium))
                .foregroundStyle(Color.DS.ink)
                .padding(.top, Spacing.s2)
        }
        .padding(.top, Spacing.s4)
    }

    private func swatchGrid(current: PrimarySwatch) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(palette.allSwatches()) { swatch in
                Button {
                    select(swatch)
                } label: {
                    swatchCell(swatch: swatch, isSelected: swatch.id == current.id)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func swatchCell(swatch: PrimarySwatch, isSelected: Bool) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(swatch.primary.color())
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .stroke(Color.DS.sage, lineWidth: isSelected ? 3 : 0)
                        .padding(-5)
                )
            Text(swatch.name)
                .font(.DS.caption)
                .foregroundStyle(isSelected ? Color.DS.ink : Color.DS.fg2)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    /// Atomic theme + icon swap. Both happen on the main actor so the
    /// preview tile updates in lockstep. Icon swap can fail (rare —
    /// happens if the asset name changed without the build setting
    /// being updated), but we don't surface that error here; the
    /// theme part still applied.
    private func select(_ swatch: PrimarySwatch) {
        UISelectionFeedbackGenerator().selectionChanged()
        ThemeStore.shared.select(swatch)
        guard let choice = AppIconChoice.from(themeId: swatch.id) else { return }
        UIApplication.shared.setAlternateIconName(choice.alternateIconName) { _ in
            // Errors are intentionally swallowed — Settings → App Icon
            // will surface any persistent issues. Bigger concern at
            // onboarding time is keeping the flow moving.
        }
    }
}
