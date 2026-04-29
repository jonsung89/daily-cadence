import PhotosUI
import SwiftUI

/// Pushed from Settings → Profile. Lets the user change their photo +
/// first/last name. Modern iOS pattern: push detail screen, edit,
/// tap **Save** in the toolbar to commit. Back button discards
/// pending name changes silently (matches Apple Settings.app).
///
/// Photo upload commits immediately when the crop sheet's "Use
/// Photo" button is tapped — that's a destructive op (replaces the
/// previous photo), so we don't want it queued behind a Save tap.
/// Name changes are queued until Save.
struct ProfileEditorScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var saving: Bool = false
    @State private var saveError: String?
    @State private var photoPicker = ProfilePhotoPickerState()

    @FocusState private var focusedField: Field?
    private enum Field { case first, last }

    private var initials: String {
        let f = firstName.first.map { String($0) } ?? ""
        let l = lastName.first.map { String($0) } ?? ""
        return (f + l).uppercased()
    }

    private var trimmedFirst: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedLast: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Save is enabled only when both fields are non-empty AND
    /// either name differs from the currently-stored value. Avoids
    /// pointless round-trips for unchanged saves.
    private var canSave: Bool {
        guard !saving, !trimmedFirst.isEmpty, !trimmedLast.isEmpty else { return false }
        let currentFirst = (AuthStore.shared.firstName ?? "")
        let currentLast = (AuthStore.shared.lastName ?? "")
        return trimmedFirst != currentFirst || trimmedLast != currentLast
    }

    var body: some View {
        let auth = AuthStore.shared
        return List {
            Section {
                avatarRow
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                fieldRow(label: "First name", text: $firstName, contentType: .givenName, field: .first)
                fieldRow(label: "Last name", text: $lastName, contentType: .familyName, field: .last)
            } header: {
                Text("Name")
            }

            if let email = auth.email, !email.isEmpty {
                Section {
                    HStack {
                        Text("Email")
                            .foregroundStyle(Color.DS.ink)
                        Spacer()
                        Text(email)
                            .foregroundStyle(Color.DS.fg2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .listRowBackground(Color.DS.bg2)
                } footer: {
                    Text("From your sign-in. Can't be changed here.")
                }
            }

            if let error = saveError ?? photoPicker.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(Color.DS.workout)
                        .font(.DS.small)
                        .listRowBackground(Color.DS.bg2)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.DS.bg1)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await runSave() }
                }
                .fontWeight(.semibold)
                .tint(Color.DS.sageDeep)
                .disabled(!canSave)
            }
        }
        .onAppear {
            firstName = AuthStore.shared.firstName ?? ""
            lastName = AuthStore.shared.lastName ?? ""
        }
        .profilePhotoCropSheet(state: photoPicker, userId: AuthStore.shared.currentUserId)
    }

    /// Tappable avatar at the top — a 96pt sage circle with the
    /// current photo (if any) or initials. PhotosPicker wraps it so
    /// the whole circle is the tap target. Below, a small "Change
    /// Photo" / "Add Photo" link for affordance + a subtle "Remove"
    /// link when a photo is set.
    private var avatarRow: some View {
        let path = AuthStore.shared.profileImagePath
        return VStack(spacing: 14) {
            PhotosPicker(
                selection: $photoPicker.pickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        Circle()
                            .fill(Color.DS.sage)
                        if let path {
                            ProfileAvatarImage(path: path)
                                .clipShape(Circle())
                        } else if !initials.isEmpty {
                            Text(initials)
                                .font(.DS.serif(size: 36, weight: .medium))
                                .foregroundStyle(Color.DS.fgOnAccent)
                        } else {
                            PlantSprout()
                                .stroke(
                                    Color.DS.fgOnAccent.opacity(0.55),
                                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                                )
                                .frame(width: 44, height: 60)
                        }
                        if photoPicker.uploading {
                            Circle().fill(Color.black.opacity(0.35))
                            ProgressView().tint(Color.DS.fgOnAccent)
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())

                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.DS.sage)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.DS.bg2))
                        .overlay(Circle().stroke(Color.DS.border1, lineWidth: 1))
                        .offset(x: 4, y: 4)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 16) {
                Text(path == nil ? "Add Photo" : "Change Photo")
                    .font(.DS.small.weight(.medium))
                    .foregroundStyle(Color.DS.sage)

                if path != nil {
                    Button(role: .destructive) {
                        Task { await photoPicker.clearPhoto() }
                    } label: {
                        Text("Remove")
                            .font(.DS.small.weight(.medium))
                    }
                }
            }
        }
        .padding(.vertical, Spacing.s4)
        .frame(maxWidth: .infinity)
    }

    private func fieldRow(
        label: String,
        text: Binding<String>,
        contentType: UITextContentType,
        field: Field
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.DS.ink)
                .frame(width: 100, alignment: .leading)
            TextField(label, text: text)
                .focused($focusedField, equals: field)
                .textContentType(contentType)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color.DS.ink)
        }
        .listRowBackground(Color.DS.bg2)
    }

    @MainActor
    private func runSave() async {
        saving = true
        defer { saving = false }
        do {
            try await AuthStore.shared.updateProfile(
                firstName: trimmedFirst,
                lastName: trimmedLast
            )
            saveError = nil
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
