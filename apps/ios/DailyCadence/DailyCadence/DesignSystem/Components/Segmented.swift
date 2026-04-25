import SwiftUI

/// One option in a `Segmented` control.
struct SegmentedOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let systemImage: String?

    init(id: ID, title: String, systemImage: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

/// A pill-shaped segmented control matching `.segmented` / `.seg.on` in
/// `design/claude-design-system/ui_kits/mobile/mobile.css`:
/// - Taupe track, fully-rounded pill corners
/// - Inactive segment: `fg-2`, 500 weight, transparent bg
/// - Active segment: `bg-2` fill, `ink` text, 600 weight, warm-ink shadow
/// - 14pt leading icon (optional), 12pt label, 7pt×14pt padding per segment
/// - 140ms easeOut animation on selection change
struct Segmented<ID: Hashable>: View {
    let options: [SegmentedOption<ID>]
    @Binding var selection: ID

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                segment(for: option)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.DS.taupe))
    }

    private func segment(for option: SegmentedOption<ID>) -> some View {
        let isActive = selection == option.id
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                selection = option.id
            }
        } label: {
            HStack(spacing: 6) {
                if let systemImage = option.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .regular))
                }
                Text(option.title)
                    .font(.DS.sans(size: 12, weight: isActive ? .semibold : .medium))
            }
            .foregroundStyle(isActive ? Color.DS.ink : Color.DS.fg2)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isActive ? Color.DS.bg2 : Color.clear)
                    .shadow(
                        color: isActive ? Color(hex: 0x2C2620, opacity: 0.08) : .clear,
                        radius: 1,
                        y: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Previews

private enum PreviewMode: Hashable { case timeline, cards }

private struct SegmentedPreviewHarness: View {
    @State private var selection: PreviewMode = .timeline

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Segmented(
                options: [
                    .init(id: .timeline, title: "Timeline", systemImage: "list.bullet"),
                    .init(id: .cards,    title: "Cards",    systemImage: "square.grid.2x2"),
                ],
                selection: $selection
            )

            Segmented(
                options: [
                    .init(id: .timeline, title: "Today"),
                    .init(id: .cards,    title: "This week"),
                ],
                selection: $selection
            )

            Text("Selected: \(String(describing: selection))")
                .font(.DS.small)
                .foregroundStyle(Color.DS.fg2)
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.DS.bg1)
    }
}

#Preview("Light") {
    SegmentedPreviewHarness()
}

#Preview("Dark") {
    SegmentedPreviewHarness().preferredColorScheme(.dark)
}
