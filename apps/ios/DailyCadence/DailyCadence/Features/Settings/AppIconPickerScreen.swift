import SwiftUI
import UIKit

/// Phase F.1.2.appicon — Settings → App Icon. Grid of 8 home-screen
/// icon variants (one per primary theme color); the currently-active
/// icon is highlighted with a sage ring. Tapping a cell calls
/// `UIApplication.setAlternateIconName` — iOS shows its own
/// "DailyCadence has changed icons" confirmation alert before applying;
/// our state updates after that succeeds.
///
/// Includes a toggle at the bottom to re-enable the theme-change ↔
/// icon-suggest prompt if the user previously dismissed it via "Don't
/// ask again."
struct AppIconPickerScreen: View {
    /// Mirrors `UIApplication.shared.alternateIconName` so the
    /// highlighted cell stays in sync with what's actually installed.
    /// Reads on appear; updates after a successful set call.
    @State private var current: AppIconChoice = .sage
    @State private var lastError: String?

    /// Reads the don't-ask flag so the toggle reflects the persisted
    /// state, and writes back through the store on toggle.
    @Bindable private var prefs = AppPreferencesStore.shared

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 16),
        count: 4
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                iconSection(
                    title: "Plant",
                    choices: AppIconChoice.allCases.filter { $0.isPlant }
                )
                iconSection(
                    title: "Quote",
                    choices: AppIconChoice.allCases.filter { !$0.isPlant }
                )

                if let lastError {
                    Text(lastError)
                        .font(.DS.small)
                        .foregroundStyle(Color.DS.workout)
                        .padding(.horizontal, 20)
                }

                Toggle(isOn: askOnThemeChangeBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ask when theme color changes")
                            .foregroundStyle(Color.DS.ink)
                        Text("When you pick a new theme color in Appearance, we'll offer to update the app icon to match.")
                            .font(.DS.small)
                            .foregroundStyle(Color.DS.fg2)
                    }
                }
                .padding(.horizontal, 20)
                .tint(Color.DS.sage)
            }
            .padding(.bottom, 32)
        }
        .background(Color.DS.bg1)
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            current = AppIconChoice.from(alternateIconName: UIApplication.shared.alternateIconName)
        }
    }

    // MARK: - Section

    @ViewBuilder
    private func iconSection(title: String, choices: [AppIconChoice]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.DS.caption)
                .foregroundStyle(Color.DS.fg2)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(choices) { choice in
                    cell(for: choice)
                        .onTapGesture { select(choice) }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Cell

    @ViewBuilder
    private func cell(for choice: AppIconChoice) -> some View {
        let selected = choice == current
        VStack(spacing: 8) {
            ThemeIconPreview(choice: choice, size: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            selected ? Color.DS.sage : Color.DS.border1,
                            lineWidth: selected ? 3 : 0.5
                        )
                )
            Text(choice.displayName)
                .font(.DS.small)
                .foregroundStyle(selected ? Color.DS.ink : Color.DS.fg2)
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(choice.displayName) icon\(selected ? ", selected" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Actions

    /// Two-way binding for the toggle. Reads the inverse of
    /// `iconSyncPromptDismissed` (toggle ON = prompt enabled), writes
    /// the inverse back. Keeps the persisted flag's name semantically
    /// honest ("dismissed = true means stop prompting").
    private var askOnThemeChangeBinding: Binding<Bool> {
        Binding(
            get: { !prefs.iconSyncPromptDismissed },
            set: { prefs.iconSyncPromptDismissed = !$0 }
        )
    }

    private func select(_ choice: AppIconChoice) {
        guard choice != current else { return }
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(choice.alternateIconName)
                current = choice
                lastError = nil
            } catch {
                lastError = "Couldn't change app icon: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Preview cell

/// Picker-thumbnail rendering of a theme icon. Doesn't use
/// `UIImage(named:)` — alternate-icon assets aren't exposed via the
/// image-name API. Re-renders the same shape (solid tile + Manrope-
/// bold opening quote, ink-centered) at any size requested.
struct ThemeIconPreview: View {
    let choice: AppIconChoice
    let size: CGFloat

    var body: some View {
        ZStack {
            choice.tileColor
            if choice.isPlant {
                // Plant variant: same `PlantSprout` shape and exact
                // proportions as the onboarding Profile-page
                // default-state plant inside the avatar circle.
                // 0.458 × 0.625 of tile, ~1.9% stroke at 55% opacity.
                // Matches the bundled rendered PNGs.
                PlantSprout()
                    .stroke(
                        choice.glyphColor.opacity(0.55),
                        style: StrokeStyle(lineWidth: size * 0.019, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: size * 0.458, height: size * 0.625)
            } else {
                Text("\u{201C}")
                    .font(.DS.manropeExtraBold(size: size * 1.03))
                    .foregroundStyle(choice.glyphColor)
                    // Same downward optical-center nudge as the in-app
                    // `DailyCadenceLogomark` (SwiftUI Text positions by
                    // typographic bounds, leaving the ink visually high).
                    .offset(y: size * 0.185)
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview("Picker") {
    NavigationStack { AppIconPickerScreen() }
}
