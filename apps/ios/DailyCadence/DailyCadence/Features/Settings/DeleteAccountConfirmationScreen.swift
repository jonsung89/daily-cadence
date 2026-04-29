import SwiftUI

/// Friction-heavy confirmation surface for permanent account deletion.
///
/// Apple Review accepts a single confirmation tap, but the cost of an
/// accidental delete (everything gone, irreversible) warrants making the
/// user type their own email — a deliberate physical action that can't
/// happen by reflex. Same pattern GitHub / Linear / Notion use for
/// destructive account operations.
///
/// Pushed from Settings → Account → Delete Account row. On successful
/// deletion, `AuthStore` catches the `.userDeleted` event from
/// `authStateChanges`, clears `currentUserId`, and `RootView`'s auth
/// gate swaps to `OnboardingScreen` — this view unmounts as part of
/// that transition.
struct DeleteAccountConfirmationScreen: View {
    @State private var typed = ""
    @State private var inFlight = false
    @State private var errorMessage: String?

    var body: some View {
        let auth = AuthStore.shared
        let expected = auth.email ?? ""
        let canDelete = !expected.isEmpty
            && typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == expected.lowercased()
            && !inFlight

        List {
            warningSection
            confirmSection(expected: expected)

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Color.DS.workout)
                        .font(.DS.small)
                        .listRowBackground(Color.DS.bg2)
                }
            }

            deleteButtonSection(enabled: canDelete)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.DS.bg1)
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var warningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Label("This can't be undone", systemImage: "exclamationmark.triangle.fill")
                    .font(.DS.body.weight(.semibold))
                    .foregroundStyle(Color.DS.workout)
                Text("Deleting your account permanently removes:")
                    .foregroundStyle(Color.DS.ink)
                VStack(alignment: .leading, spacing: 4) {
                    bullet("Every note (text, stat, list, quote, media)")
                    bullet("Every photo and video you've uploaded")
                    bullet("Every custom theme and per-type color")
                    bullet("Your sign-in identity (Apple / Google)")
                }
                .foregroundStyle(Color.DS.fg2)
                .font(.DS.small)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.DS.bg2)
        }
    }

    private func confirmSection(expected: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text("Type your email to confirm")
                    .font(.DS.small)
                    .foregroundStyle(Color.DS.fg2)
                if !expected.isEmpty {
                    Text(expected)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.DS.ink)
                        .textSelection(.enabled)
                }
                TextField(expected.isEmpty ? "your email" : expected, text: $typed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .padding(.top, 2)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.DS.bg2)
        } footer: {
            if expected.isEmpty {
                Text("This account doesn't have an email on file. Sign out and back in if you need to recover access.")
            }
        }
    }

    private func deleteButtonSection(enabled: Bool) -> some View {
        Section {
            Button(role: .destructive) {
                Task { await runDelete() }
            } label: {
                HStack {
                    Spacer()
                    Text(inFlight ? "Deleting…" : "Delete Account Permanently")
                        .font(.DS.body.weight(.semibold))
                    Spacer()
                }
            }
            .disabled(!enabled)
            .listRowBackground(Color.DS.bg2)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
        }
    }

    @MainActor
    private func runDelete() async {
        inFlight = true
        defer { inFlight = false }
        do {
            try await AuthStore.shared.deleteAccount()
            errorMessage = nil
            // RootView's auth gate handles the navigation away — this
            // view unmounts when AuthStore clears currentUserId.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Light") {
    NavigationStack {
        DeleteAccountConfirmationScreen()
    }
}

#Preview("Dark") {
    NavigationStack {
        DeleteAccountConfirmationScreen()
    }
    .preferredColorScheme(.dark)
}
