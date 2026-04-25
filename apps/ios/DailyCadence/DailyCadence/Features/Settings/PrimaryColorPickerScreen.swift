import SwiftUI

/// Detail screen pushed from Settings → Appearance → Primary color.
///
/// Lists every primary theme loaded from `PrimaryPaletteRepository`. Tapping
/// a row calls `ThemeStore.shared.select(_:)`, which persists to
/// `UserDefaults` and triggers re-render of every view reading
/// `Color.DS.sage` / `sageDeep` / `sageSoft` — the user sees the accent
/// change live across the app while standing on this screen.
///
/// The screen doesn't pop automatically; iOS convention is to let the user
/// try a few options and navigate back when ready. A checkmark marks the
/// active selection in the row's trailing accessory.
struct PrimaryColorPickerScreen: View {
    @State private var selectedId: String
    private let swatches: [PrimarySwatch]

    init(
        swatches: [PrimarySwatch] = PrimaryPaletteRepository.shared.allSwatches(),
        initialSelection: String = ThemeStore.shared.primary.id
    ) {
        self.swatches = swatches
        _selectedId = State(initialValue: initialSelection)
    }

    var body: some View {
        List {
            Section {
                ForEach(swatches) { swatch in
                    pickerRow(swatch)
                        .listRowBackground(Color.DS.bg2)
                }
            } footer: {
                Text("Changes the app's accent color — buttons, the floating + button, selected tabs. Note-type colors (workout, meal, sleep, mood, activity) stay fixed so the timeline keeps its data legend.")
                    .font(.DS.small)
                    .foregroundStyle(Color.DS.fg2)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.DS.bg1)
        .navigationTitle("Primary color")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pickerRow(_ swatch: PrimarySwatch) -> some View {
        Button {
            ThemeStore.shared.select(swatch)
            selectedId = swatch.id
        } label: {
            HStack(spacing: 14) {
                PrimaryTrioDots(swatch: swatch, dotSize: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(swatch.name)
                        .font(.DS.body)
                        .foregroundStyle(Color.DS.ink)
                    if let description = swatch.description {
                        Text(description)
                            .font(.DS.small)
                            .foregroundStyle(Color.DS.fg2)
                    }
                }
                Spacer(minLength: 8)
                if swatch.id == selectedId {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(swatch.primary.color())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(swatch.id == selectedId ? .isSelected : [])
    }
}

/// A small preview of a primary swatch's trio — three overlapping circles
/// representing `primary` / `deep` / `soft`.
///
/// Reused by Settings rows and the debug design gallery. Stroke separates
/// adjacent circles so overlapping edges stay visually readable.
struct PrimaryTrioDots: View {
    let swatch: PrimarySwatch
    var dotSize: CGFloat = 22
    var separator: Color = .DS.bg2

    var body: some View {
        HStack(spacing: -dotSize * 0.27) {
            dot(swatch.primary.color())
            dot(swatch.deep.color())
            dot(swatch.soft.color())
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: dotSize, height: dotSize)
            .overlay(
                Circle()
                    .stroke(separator, lineWidth: dotSize * 0.09)
            )
    }
}

#Preview("Picker") {
    NavigationStack {
        PrimaryColorPickerScreen()
    }
}

#Preview("Picker, dark") {
    NavigationStack {
        PrimaryColorPickerScreen()
    }
    .preferredColorScheme(.dark)
}
