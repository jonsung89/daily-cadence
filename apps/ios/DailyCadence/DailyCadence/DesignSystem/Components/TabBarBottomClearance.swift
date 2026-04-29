import SwiftUI

extension View {
    /// Adds bottom safe-area clearance for tab-content screens whose root
    /// scroll container is a `List` (especially with
    /// `.scrollContentBackground(.hidden)` + a custom `.background(...)`).
    ///
    /// **Why this exists.** RootView mounts the custom `TabBar` via
    /// `.safeAreaInset(edge: .bottom)`. SwiftUI is supposed to propagate
    /// that inset to all descendants — and for plain ScrollViews / VStacks
    /// it does. But on iOS 26, the combination `NavigationStack { List
    /// .listStyle(.insetGrouped) .scrollContentBackground(.hidden)
    /// .background(...) }` swallows the bottom inset, and the last row in
    /// the List ends up obscured by the translucent TabBar. `contentMargins`
    /// on `List` is also unreliable for the same reason. The verified
    /// workaround is a clear-color spacer wrapped in another
    /// `.safeAreaInset(.bottom)` — same trick `StylePickerView` uses.
    ///
    /// Apply this **once** to any tab-content screen with a List/ScrollView
    /// root that doesn't have its own bottom-overlay (FAB, toolbar). For
    /// screens that already add their own bottom clearance (like
    /// `TimelineScreen` with its FAB), don't double it up.
    ///
    /// 100pt is sized to clear the 88pt TabBar with breathing room.
    /// Reduce/increase via the `extra` parameter if a screen needs tighter
    /// or looser spacing.
    func tabBarBottomClearance(extra: CGFloat = 0) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 100 + extra)
        }
    }
}
