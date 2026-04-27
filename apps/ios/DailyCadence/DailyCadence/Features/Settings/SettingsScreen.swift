import SwiftUI

/// The Settings tab.
///
/// Phase B scope: a real Settings surface with the Primary color picker
/// wired up. Additional rows (notifications, data, profile, sign out) land
/// incrementally as those features come online — don't stub them here with
/// "coming soon" placeholders; empty sections are louder than no section at
/// all.
struct SettingsScreen: View {
    var body: some View {
        NavigationStack {
            List {
                todaySection
                appearanceSection
                accountSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.DS.bg1)
            .navigationTitle("Settings")
        }
    }

    // MARK: - Today

    /// Behavioral preferences for the Today screen (Phase E.5).
    private var todaySection: some View {
        @Bindable var prefs = AppPreferencesStore.shared
        return Section {
            Picker(selection: $prefs.defaultTodayView) {
                ForEach(TimelineViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            } label: {
                Text("Default view")
                    .foregroundStyle(Color.DS.ink)
            }
            .listRowBackground(Color.DS.bg2)
        } header: {
            Text("Today")
        } footer: {
            Text("Picks which view the Today tab opens in by default.")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            NavigationLink {
                PrimaryColorPickerScreen()
            } label: {
                PrimaryColorRow()
            }
            .listRowBackground(Color.DS.bg2)

            NavigationLink {
                NoteTypePickerScreen()
            } label: {
                NoteTypesRow()
            }
            .listRowBackground(Color.DS.bg2)
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Account

    /// Shows the current Supabase auth state. Phase F dev mode signs in
    /// anonymously, so this displays a uuid that's stable per install
    /// (until the device's Keychain entry is cleared). Replaces the
    /// "Loading…" placeholder once `AuthStore` has bootstrapped.
    private var accountSection: some View {
        let auth = AuthStore.shared
        return Section {
            HStack {
                Text("User ID")
                    .foregroundStyle(Color.DS.ink)
                Spacer()
                Text(accountStatusText(auth: auth))
                    .foregroundStyle(Color.DS.fg2)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .listRowBackground(Color.DS.bg2)

            if let error = auth.lastError {
                HStack {
                    Text("Error")
                        .foregroundStyle(Color.DS.ink)
                    Spacer()
                    Text(error)
                        .foregroundStyle(Color.DS.workout)
                        .font(.DS.small)
                        .multilineTextAlignment(.trailing)
                }
                .listRowBackground(Color.DS.bg2)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Phase F dev mode: anonymous Supabase session. Apple + Google sign-in land once Apple Developer enrollment clears.")
        }
    }

    private func accountStatusText(auth: AuthStore) -> String {
        if let id = auth.currentUserId {
            return id.uuidString
        }
        return auth.isReady ? "—" : "Loading…"
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundStyle(Color.DS.ink)
                Spacer()
                Text(appVersion)
                    .foregroundStyle(Color.DS.fg2)
                    .font(.system(size: 15, design: .monospaced))
            }
            .listRowBackground(Color.DS.bg2)

            HStack {
                Text("Build")
                    .foregroundStyle(Color.DS.ink)
                Spacer()
                Text(buildNumber)
                    .foregroundStyle(Color.DS.fg2)
                    .font(.system(size: 15, design: .monospaced))
            }
            .listRowBackground(Color.DS.bg2)
        } header: {
            Text("About")
        }
    }

    // MARK: - App version helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

/// Row shown inside Settings' Appearance section. Displays the current
/// primary theme's trio preview and name, with a chevron (inherited from
/// the enclosing NavigationLink).
///
/// Reading `ThemeStore.shared.primary` inside `body` registers the view as
/// an observer, so the row updates live when the user picks a new theme on
/// the detail screen.
struct PrimaryColorRow: View {
    var body: some View {
        let swatch = ThemeStore.shared.primary
        HStack(spacing: 14) {
            PrimaryTrioDots(swatch: swatch, dotSize: 18)
            Text("Primary color")
                .font(.DS.body)
                .foregroundStyle(Color.DS.ink)
            Spacer(minLength: 8)
            Text(swatch.name)
                .font(.DS.body)
                .foregroundStyle(Color.DS.fg2)
        }
    }
}

/// Row shown inside Settings' Appearance section. Five overlapping circles
/// preview each note type's CURRENT color (defaults or user overrides). Reads
/// through `NoteType.color` so changes propagate live when the user picks
/// a new color on the detail screen.
struct NoteTypesRow: View {
    var body: some View {
        // Touch the store so this view re-renders on override changes.
        let _ = NoteTypeStyleStore.shared.overrides
        return HStack(spacing: 14) {
            HStack(spacing: -6) {
                ForEach(NoteType.allCases) { type in
                    Circle()
                        .fill(type.color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.DS.bg2, lineWidth: 1.5))
                }
            }
            Text("Note Types")
                .font(.DS.body)
                .foregroundStyle(Color.DS.ink)
            Spacer(minLength: 8)
            Text(summary)
                .font(.DS.body)
                .foregroundStyle(Color.DS.fg2)
        }
    }

    private var summary: String {
        let count = NoteTypeStyleStore.shared.overrides.count
        switch count {
        case 0: return "Default"
        case 1: return "1 customized"
        default: return "\(count) customized"
        }
    }
}

#Preview("Light") {
    SettingsScreen()
}

#Preview("Dark") {
    SettingsScreen().preferredColorScheme(.dark)
}
