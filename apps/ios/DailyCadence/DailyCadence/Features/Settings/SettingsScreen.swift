import SwiftUI

/// The Settings tab.
///
/// Phase B scope: a real Settings surface with the Primary color picker
/// wired up. Additional rows (notifications, data, profile, sign out) land
/// incrementally as those features come online — don't stub them here with
/// "coming soon" placeholders; empty sections are louder than no section at
/// all.
struct SettingsScreen: View {
    @State private var signOutInFlight = false
    @State private var signOutError: String?

    var body: some View {
        NavigationStack {
            List {
                profileSection
                todaySection
                appearanceSection
                aboutSection
                accountSection
                dangerZoneSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.DS.bg1)
            .navigationTitle("Settings")
            .tabBarBottomClearance()
        }
    }

    // MARK: - Profile

    /// Top row of Settings — current avatar + name + email + chevron.
    /// Pushes `ProfileEditorScreen` for full editing. Mirrors the
    /// Apple Settings.app pattern (Apple ID at the very top of the
    /// list with photo, name, navigation chevron).
    private var profileSection: some View {
        Section {
            NavigationLink {
                ProfileEditorScreen()
            } label: {
                ProfileSettingsRow()
            }
            .listRowBackground(Color.DS.bg2)
        }
    }

    // MARK: - Today

    /// Behavioral preferences for the Today screen (Phase E.5).
    ///
    /// Hand-built `Menu` rather than `Picker` so the collapsed selected
    /// display can use the same icon-to-title spacing as the dropdown
    /// items. SwiftUI's `Picker` (and its iOS 17 `currentValueLabel:`
    /// override) renders the row's trailing display with system-tight
    /// spacing inside an inset-grouped list, ignoring custom inner
    /// layout. Going to `Menu` + manual chevron is the only reliable
    /// way to keep the two states visually consistent.
    private var todaySection: some View {
        @Bindable var prefs = AppPreferencesStore.shared
        return Section {
            Menu {
                Picker(selection: $prefs.defaultTodayView) {
                    ForEach(TimelineViewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                } label: {
                    EmptyView()
                }
            } label: {
                HStack(spacing: 0) {
                    Text("Default view")
                        .foregroundStyle(Color.DS.ink)
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: prefs.defaultTodayView.systemImage)
                        Text(prefs.defaultTodayView.title)
                    }
                    .foregroundStyle(Color.DS.sage)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Color.DS.fg2)
                        .padding(.leading, 6)
                }
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

            // Phase F.1.2.appicon — Settings → App Icon picker.
            NavigationLink {
                AppIconPickerScreen()
            } label: {
                AppIconRow()
            }
            .listRowBackground(Color.DS.bg2)
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Account

    /// Shows the signed-in identity (email when available, falls back to
    /// the user UUID for anonymous sessions left over from dev mode) and
    /// a Sign Out button. Sign Out invalidates the Supabase session;
    /// `AuthStore` then flips `currentUserId` to `nil`, which RootView
    /// observes and swaps in `OnboardingScreen`.
    private var accountSection: some View {
        let auth = AuthStore.shared
        return Section {
            HStack {
                Text("Signed in as")
                    .foregroundStyle(Color.DS.ink)
                Spacer()
                Text(identityLabel(auth: auth))
                    .foregroundStyle(Color.DS.fg2)
                    .font(.DS.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .listRowBackground(Color.DS.bg2)

            if let error = signOutError ?? auth.lastError {
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

            Button(role: .destructive) {
                Task { await runSignOut() }
            } label: {
                HStack {
                    Text(signOutInFlight ? "Signing out…" : "Sign Out")
                    Spacer()
                }
            }
            .disabled(signOutInFlight || auth.currentUserId == nil)
            .listRowBackground(Color.DS.bg2)
        } header: {
            Text("Account")
        }
    }

    /// Permanent account deletion lives in its own section, separated
    /// from the routine "Sign Out" action so the visual weight matches
    /// the consequences (irreversible, all data gone). Modern iOS apps
    /// — GitHub, Linear, Notion — use the same "Danger Zone" pattern:
    /// system-red label + trash icon + warning footer + a typed
    /// confirmation flow on the destination screen. The row uses the
    /// same system red as `Sign Out` for visual consistency; the
    /// scarier-than-Sign-Out signal comes from the section break and
    /// the destination's email-typed confirmation, not louder color.
    private var dangerZoneSection: some View {
        let auth = AuthStore.shared
        return Section {
            NavigationLink {
                DeleteAccountConfirmationScreen()
            } label: {
                Text("Delete Account")
                    .foregroundStyle(Color.red)
            }
            .disabled(signOutInFlight || auth.currentUserId == nil)
            .listRowBackground(Color.DS.bg2)
        } header: {
            Text("Danger Zone")
                .foregroundStyle(Color.red)
        } footer: {
            Text("Permanently removes your account and every note, photo, and video. This can't be undone.")
        }
    }

    private func identityLabel(auth: AuthStore) -> String {
        if let email = auth.email, !email.isEmpty {
            return email
        }
        if let id = auth.currentUserId {
            // Anonymous session — show a short identifier so the user
            // has *something* concrete on screen. Email arrives on next
            // Apple/Google sign-in.
            return "Guest · \(id.uuidString.prefix(8))"
        }
        return auth.isReady ? "—" : "Loading…"
    }

    @MainActor
    private func runSignOut() async {
        signOutInFlight = true
        defer { signOutInFlight = false }
        do {
            try await AuthStore.shared.signOut()
            signOutError = nil
        } catch {
            signOutError = error.localizedDescription
        }
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

            #if DEBUG
            // Dev-only — replays the onboarding flow on the next gate
            // re-evaluation. Stripped from release builds; never
            // visible to TestFlight or App Store users.
            Button {
                AppPreferencesStore.shared.hasCompletedOnboarding = false
            } label: {
                HStack {
                    Text("Replay onboarding")
                        .foregroundStyle(Color.DS.ink)
                    Spacer()
                    Text("DEBUG")
                        .font(.DS.caption)
                        .foregroundStyle(Color.DS.fg2)
                }
            }
            .listRowBackground(Color.DS.bg2)
            #endif
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
            Text("Theme color")
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
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(summary)
                .font(.DS.body)
                .foregroundStyle(Color.DS.fg2)
                .lineLimit(1)
        }
    }

    private var summary: String {
        let count = NoteTypeStyleStore.shared.overrides.count
        // "Default" reads as a meaningful state when no overrides are
        // set; once the user customizes any type the trailing detail
        // becomes a bare count so the row stays compact and "Note Types"
        // (the row's identity) never has to truncate.
        return count == 0 ? "Default" : "\(count)"
    }
}

/// Phase F.1.2.appicon — Settings → App Icon row. Shows the
/// currently-installed icon as a tiny preview tile + name. Reads
/// `UIApplication.shared.alternateIconName` directly so the row stays
/// in sync with whatever the user picked (or whatever the
/// theme-change prompt installed).
struct AppIconRow: View {
    var body: some View {
        let current = AppIconChoice.from(
            alternateIconName: UIApplication.shared.alternateIconName
        )
        return HStack(spacing: 14) {
            ThemeIconPreview(choice: current, size: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text("App Icon")
                .font(.DS.body)
                .foregroundStyle(Color.DS.ink)
            Spacer(minLength: 8)
            Text(current.displayName)
                .font(.DS.body)
                .foregroundStyle(Color.DS.fg2)
        }
    }
}

#Preview("Light") {
    SettingsScreen()
}

#Preview("Dark") {
    SettingsScreen().preferredColorScheme(.dark)
}

/// Row at the top of Settings: the user's current photo + name +
/// email. Tappable; pushes `ProfileEditorScreen`. Reads from
/// `AuthStore` — Observation framework re-renders the row when name
/// or photo path change, so editor saves reflect here immediately.
struct ProfileSettingsRow: View {
    var body: some View {
        let auth = AuthStore.shared
        let path = auth.profileImagePath
        let displayName = displayName(auth: auth)
        let initials = initials(auth: auth)

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.DS.sage)
                if let path {
                    ProfileAvatarImage(path: path)
                        .clipShape(Circle())
                } else if !initials.isEmpty {
                    Text(initials)
                        .font(.DS.serif(size: 18, weight: .medium))
                        .foregroundStyle(Color.DS.fgOnAccent)
                } else {
                    PlantSprout()
                        .stroke(
                            Color.DS.fgOnAccent.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 22, height: 30)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.DS.body.weight(.semibold))
                    .foregroundStyle(Color.DS.ink)
                    .lineLimit(1)
                if let email = auth.email, !email.isEmpty {
                    Text(email)
                        .font(.DS.small)
                        .foregroundStyle(Color.DS.fg2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }

    private func displayName(auth: AuthStore) -> String {
        let parts = [auth.firstName, auth.lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return "Add your name"
    }

    private func initials(auth: AuthStore) -> String {
        let f = auth.firstName?.first.map { String($0) } ?? ""
        let l = auth.lastName?.first.map { String($0) } ?? ""
        return (f + l).uppercased()
    }
}
