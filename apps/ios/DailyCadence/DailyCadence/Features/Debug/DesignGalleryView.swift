import SwiftUI

/// A visual catalog of everything loaded from `PaletteRepository`,
/// `PrimaryPaletteRepository`, and `FontRepository`. Not wired into the
/// running app — opened through SwiftUI Previews as a QA tool before we
/// build the real Settings UI (Phase B) and the Note Editor style picker
/// (Phase C+).
///
/// When the admin panel ships (Phase F) and we start editing the JSON
/// remotely, this gallery is the quickest way to eyeball the output.
struct DesignGalleryView: View {
    @State private var activeThemeId: String = ThemeStore.shared.primary.id

    private let paletteRepo: PaletteRepository = .shared
    private let primaryRepo: PrimaryPaletteRepository = .shared
    private let fontRepo: FontRepository = .shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                primarySection
                notePaletteSection
                fontSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color.DS.bg1)
    }

    // MARK: - Primary swatches

    private var primarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Primary themes")
            Text("Tap a trio to swap the app's primary color at runtime. The sage/deep/soft columns come from `primary-palettes.json`.")
                .font(.DS.small)
                .foregroundStyle(Color.DS.fg2)

            VStack(spacing: 8) {
                ForEach(primaryRepo.allSwatches()) { swatch in
                    primaryRow(swatch)
                }
            }

            Button("Reset to default (sage)") {
                ThemeStore.shared.resetToDefault()
                activeThemeId = ThemeStore.shared.primary.id
            }
            .font(.DS.label)
            .padding(.top, 4)
        }
    }

    private func primaryRow(_ swatch: PrimarySwatch) -> some View {
        let isActive = swatch.id == activeThemeId
        return Button {
            ThemeStore.shared.select(swatch)
            activeThemeId = swatch.id
        } label: {
            HStack(spacing: 12) {
                trioDots(swatch)
                VStack(alignment: .leading, spacing: 2) {
                    Text(swatch.name)
                        .font(.DS.sans(size: 15, weight: .semibold))
                        .foregroundStyle(Color.DS.ink)
                    if let description = swatch.description {
                        Text(description)
                            .font(.DS.sans(size: 12))
                            .foregroundStyle(Color.DS.fg2)
                    }
                }
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(swatch.primary.color())
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color.DS.bg2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(isActive ? swatch.primary.color() : Color.DS.border1, lineWidth: isActive ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func trioDots(_ swatch: PrimarySwatch) -> some View {
        HStack(spacing: -6) {
            Circle().fill(swatch.primary.color()).frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.DS.bg2, lineWidth: 2))
            Circle().fill(swatch.deep.color()).frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.DS.bg2, lineWidth: 2))
            Circle().fill(swatch.soft.color()).frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.DS.bg2, lineWidth: 2))
        }
    }

    // MARK: - Note-background palettes

    private var notePaletteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Note background palettes")
            Text("Per-note background colors. Each swatch is applied at ~33% opacity inside a KeepCard; the sample below shows the raw value.")
                .font(.DS.small)
                .foregroundStyle(Color.DS.fg2)

            ForEach(paletteRepo.allPalettes()) { palette in
                paletteBlock(palette)
            }
        }
    }

    private func paletteBlock(_ palette: ColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(palette.name)
                    .font(.DS.sans(size: 14, weight: .semibold))
                    .foregroundStyle(Color.DS.ink)
                if let description = palette.description {
                    Text(description)
                        .font(.DS.sans(size: 12))
                        .foregroundStyle(Color.DS.fg2)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 80), spacing: 8)],
                spacing: 8
            ) {
                ForEach(palette.swatches) { swatch in
                    swatchTile(swatch)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.DS.bg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.DS.border1, lineWidth: 1)
        )
    }

    private func swatchTile(_ swatch: Swatch) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(swatch.color())
                .frame(height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(Color.DS.border1, lineWidth: 0.5)
                )
            Text(swatch.name)
                .font(.DS.sans(size: 10, weight: .medium))
                .foregroundStyle(Color.DS.fg2)
                .lineLimit(1)
        }
    }

    // MARK: - Fonts

    private var fontSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Fonts")
            Text("Every font in `fonts.json`, rendered at 18pt. `iosBuiltIn` and `system` entries use zero bundle bytes.")
                .font(.DS.small)
                .foregroundStyle(Color.DS.fg2)

            VStack(spacing: 10) {
                ForEach(fontRepo.allFonts()) { definition in
                    fontRow(definition)
                }
            }
        }
    }

    private func fontRow(_ definition: NoteFontDefinition) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.displayName)
                    .font(.DS.sans(size: 11, weight: .bold))
                    .tracking(0.88)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.DS.fg2)
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(definition.font(size: 18))
                    .foregroundStyle(Color.DS.ink)
            }
            Spacer(minLength: 8)
            Text(definition.source.rawValue)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.DS.fg2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.DS.bg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.DS.border1, lineWidth: 1)
        )
    }
}

#Preview("Light") {
    DesignGalleryView()
}

#Preview("Dark") {
    DesignGalleryView()
        .preferredColorScheme(.dark)
}
