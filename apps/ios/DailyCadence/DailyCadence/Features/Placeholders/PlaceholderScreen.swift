import SwiftUI

/// A simple "coming soon" placeholder used for tabs that aren't implemented
/// yet. Keeps the app shell navigable end-to-end during Phase 1.
struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let summary: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.DS.fg2)
                Text(title)
                    .font(.DS.h2)
                    .foregroundStyle(Color.DS.ink)
                Text(summary)
                    .font(.DS.body)
                    .foregroundStyle(Color.DS.fg2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                SectionLabel("Coming soon")
                    .padding(.top, 4)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.DS.bg1)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview("Calendar placeholder") {
    PlaceholderScreen(
        title: "Calendar",
        systemImage: "calendar",
        summary: "A monthly view of everything you've logged. Tap a day to see the full timeline."
    )
}

#Preview("Dark") {
    PlaceholderScreen(
        title: "Progress",
        systemImage: "chart.line.uptrend.xyaxis",
        summary: "Exercise progression charts, macro trends, and sleep patterns."
    )
    .preferredColorScheme(.dark)
}
