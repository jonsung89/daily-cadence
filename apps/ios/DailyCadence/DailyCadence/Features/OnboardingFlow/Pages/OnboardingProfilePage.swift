import PhotosUI
import SwiftUI

/// Profile page — collects first + last name + an optional profile
/// photo. Names pre-fill from `AuthStore.firstName` / `lastName`
/// (sourced from the OAuth provider's user metadata) and save through
/// `AuthStore.updateProfile`. Photo flows through `ProfilePhotoPicker`
/// which handles PhotosPicker → square crop → Storage upload →
/// metadata write.
struct OnboardingProfilePage: View {
    @Binding var firstName: String
    @Binding var lastName: String
    let pageIndex: Int
    let pageCount: Int
    let isSaving: Bool
    let saveError: String?
    let onContinue: () -> Void

    @State private var photoPicker = ProfilePhotoPickerState()
    @FocusState private var focusedField: Field?
    private enum Field { case first, last }

    /// Initials shown inside the avatar when there's no profile photo.
    /// Empty string when neither field has content yet — the avatar
    /// then renders the journal-pen plant placeholder instead of the
    /// awkward "?" we used to ship.
    private var initials: String {
        let first = firstName.first.map { String($0) } ?? ""
        let last = lastName.first.map { String($0) } ?? ""
        return (first + last).uppercased()
    }

    private var canContinue: Bool {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isSaving && !photoPicker.uploading && !first.isEmpty && !last.isEmpty
    }

    var body: some View {
        OnboardingChrome(
            pageIndex: pageIndex,
            pageCount: pageCount,
            canSkip: false,
            title: "Tell us about yourself",
            primaryLabel: isSaving ? "Saving…" : "Continue",
            isPrimaryEnabled: canContinue,
            onPrimary: onContinue
        ) {
            avatar
        } control: {
            VStack(spacing: Spacing.s3) {
                fieldStack
                if let combinedError {
                    Text(combinedError)
                        .font(.DS.small)
                        .foregroundStyle(Color.DS.workout)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .profilePhotoCropSheet(state: photoPicker, userId: AuthStore.shared.currentUserId)
    }

    /// Combine save + photo errors into one inline surface so the page
    /// never has two stacked error bars competing for attention.
    private var combinedError: String? {
        if let saveError { return saveError }
        return photoPicker.errorMessage
    }

    /// Avatar wrapped in journal-pen ornaments so the Profile page
    /// has the same visual depth as Welcome / Reminders / Done.
    /// Tap → PhotosPicker → square crop → upload. Display priority:
    /// uploaded photo (if path on `AuthStore`) → initials (if names
    /// typed) → hand-drawn plant placeholder.
    private var avatar: some View {
        let primary = ThemeStore.shared.primary.deep.color()
        let path = AuthStore.shared.profileImagePath

        return ZStack {
            // Surrounding ornaments — kept identical to before so the
            // composition still reads as a Profile-page hero.
            SunMark(rayCount: 6)
                .stroke(
                    primary.opacity(0.40),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 30, height: 30)
                .offset(x: 78, y: -52)

            SparkleMark()
                .stroke(
                    primary.opacity(0.30),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 10, height: 10)
                .offset(x: 70, y: 56)

            Circle()
                .fill(primary.opacity(0.35))
                .frame(width: 4, height: 4)
                .offset(x: -88, y: 36)

            Circle()
                .fill(primary.opacity(0.30))
                .frame(width: 3, height: 3)
                .offset(x: 92, y: 18)

            // PhotosPicker wraps the avatar so a tap on the circle
            // opens the picker. Custom label = the avatar visuals.
            PhotosPicker(
                selection: $photoPicker.pickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                avatarStack(path: path)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 240, height: 160)
        .padding(.top, Spacing.s2)
        .animation(.easeInOut(duration: 0.2), value: initials.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: path)
    }

    /// The 96×96 sage circle plus its content layer (photo / initials /
    /// plant) and an "Edit" affordance pinned to the bottom-right so
    /// the user knows it's tappable.
    private func avatarStack(path: String?) -> some View {
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
                        .transition(.opacity)
                } else {
                    PlantSprout()
                        .stroke(
                            Color.DS.fgOnAccent.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 44, height: 60)
                        .transition(.opacity)
                }

                if photoPicker.uploading {
                    Circle().fill(Color.black.opacity(0.35))
                    ProgressView().tint(Color.DS.fgOnAccent)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())

            // Tiny edit badge so the user knows the avatar is tappable.
            Image(systemName: "camera.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.DS.sage)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.DS.bg2))
                .overlay(Circle().stroke(Color.DS.border1, lineWidth: 1))
                .offset(x: 4, y: 4)
        }
    }

    private var fieldStack: some View {
        VStack(spacing: 12) {
            field(label: "First name", text: $firstName, contentType: .givenName, field: .first)
            field(label: "Last name", text: $lastName, contentType: .familyName, field: .last)
        }
    }

    private func field(
        label: String,
        text: Binding<String>,
        contentType: UITextContentType,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.DS.caption)
                .foregroundStyle(Color.DS.fg2)
            TextField(label, text: text)
                .focused($focusedField, equals: field)
                .textContentType(contentType)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.DS.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(Color.DS.border1, lineWidth: 1)
                )
        }
    }
}
