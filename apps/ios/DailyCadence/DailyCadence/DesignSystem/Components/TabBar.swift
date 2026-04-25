import SwiftUI

/// A tab item descriptor for `TabBar`.
///
/// `id` is any `Hashable` value — typically an enum case representing the tab
/// (e.g. `RootTab.timeline`). Bind `TabBar` against a `@State` or `@Binding`
/// of the same type.
struct TabBarItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let systemImage: String
    let accessibilityLabel: String?

    init(
        id: ID,
        title: String,
        systemImage: String,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Custom bottom tab bar.
///
/// Matches `.tabbar` / `.tab` / `.tab.active` in `mobile.css`:
/// - 88pt total height (56pt content + 28pt safe-area bottom in the CSS)
/// - Translucent cream backdrop with 12pt blur
/// - 1pt `border-1` top stroke
/// - 5-column equal grid
/// - Inactive tab: `fg-2`, 22pt SF Symbol, 10pt 500-weight label
/// - Active tab: `sage-deep`, same icon + label, plus a 4pt sage-deep dot below
///
/// The caller is responsible for positioning the tab bar at the bottom of
/// the screen (typically via `.safeAreaInset(edge: .bottom)` on the content).
/// This view's intrinsic height includes the bottom safe-area padding so it
/// can be used directly as a safe-area inset.
struct TabBar<ID: Hashable>: View {
    let items: [TabBarItem<ID>]
    @Binding var selection: ID

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                TabBarButton(
                    item: item,
                    isSelected: selection == item.id
                ) {
                    selection = item.id
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)  // breathing room above the home-indicator zone
        .background {
            // Background extends down into the bottom safe area (home-indicator
            // zone) so the blur covers the full strip — without this, scroll
            // content showed through the ~34pt gap below the icons.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.DS.bg1.opacity(0.72))
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.DS.border1)
                .frame(height: 1)
        }
    }
}

private struct TabBarButton<ID: Hashable>: View {
    let item: TabBarItem<ID>
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .frame(height: 22)
                Text(item.title)
                    .font(.DS.sans(size: 10, weight: .medium))
                Circle()
                    .fill(isSelected ? Color.DS.sageDeep : Color.clear)
                    .frame(width: 4, height: 4)
                    .padding(.top, 1)
            }
            .foregroundStyle(isSelected ? Color.DS.sageDeep : Color.DS.fg2)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel ?? item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

private enum PreviewTab: Hashable {
    case timeline, calendar, add, dashboard, settings
}

private struct TabBarPreviewHarness: View {
    @State private var selection: PreviewTab = .timeline

    private var items: [TabBarItem<PreviewTab>] {
        [
            .init(id: .timeline,  title: "Today",     systemImage: "list.bullet"),
            .init(id: .calendar,  title: "Calendar",  systemImage: "calendar"),
            .init(id: .add,       title: "Add",       systemImage: "plus.circle"),
            .init(id: .dashboard, title: "Progress",  systemImage: "chart.line.uptrend.xyaxis"),
            .init(id: .settings,  title: "Settings",  systemImage: "gearshape"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filler content so the blur has something to blur over
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(0..<12, id: \.self) { i in
                        NoteCard(
                            type: NoteType.allCases[i % NoteType.allCases.count],
                            title: "Sample note \(i + 1)",
                            message: "A body line to give the tab bar something visible to blur over."
                        )
                    }
                }
                .padding(20)
            }
            .background(Color.DS.bg1)
            TabBar(items: items, selection: $selection)
        }
    }
}

#Preview("Light") {
    TabBarPreviewHarness()
}

#Preview("Dark") {
    TabBarPreviewHarness()
        .preferredColorScheme(.dark)
}
