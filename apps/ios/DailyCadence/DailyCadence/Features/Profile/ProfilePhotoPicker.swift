import PhotosUI
import SwiftUI
import OSLog
import UIKit

/// Drives the profile-photo upload flow: PhotosPicker → square crop →
/// upload to Supabase Storage → save the new path to auth metadata.
///
/// State machine:
/// 1. Idle — `pickerItem == nil`, no crop, no upload
/// 2. Picked — user chose an item from PhotosPicker; we load bytes
/// 3. Cropping — bytes loaded into `PhotoCropState`, sheet visible
/// 4. Uploading — user confirmed crop, bytes flying to Storage
///
/// Failures surface inline; the avatar stays as it was. Square crop
/// (the underlying image is square; the avatar's `Circle` mask
/// handles the round display).
@MainActor
@Observable
final class ProfilePhotoPickerState {
    var pickerItem: PhotosPickerItem? {
        didSet { handlePickerChange() }
    }
    /// When non-nil, presents the crop sheet. Cleared on cancel/commit.
    var cropState: PhotoCropState?
    var uploading: Bool = false
    var errorMessage: String?

    private let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "ProfilePhotoPicker")

    /// Loads bytes for the picked item and advances to the crop step.
    /// PhotosPickerItem can take a moment to materialize on cellular;
    /// we keep `pickerItem` set during load so the UI can show a hint
    /// if needed. On failure we clear and surface the error.
    private func handlePickerChange() {
        guard let item = pickerItem else { return }
        Task {
            errorMessage = nil
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    errorMessage = "Couldn't read that photo. Try another one."
                    pickerItem = nil
                    return
                }
                guard let state = PhotoCropState(data: data) else {
                    errorMessage = "That photo isn't a supported image."
                    pickerItem = nil
                    return
                }
                state.aspect = .square
                cropState = state
            } catch {
                log.error("PhotosPicker load failed: \(error.localizedDescription)")
                errorMessage = "Couldn't load that photo. Try again."
                pickerItem = nil
            }
        }
    }

    /// Confirm-side of the crop. Reads the cropped bytes, uploads to
    /// `profile-images`, and writes the path back to user metadata.
    /// Caller passes the active user id so we can build the path
    /// without round-tripping through `AuthStore`.
    func commitCrop(userId: UUID) async {
        guard let state = cropState, let result = state.commitCrop() else {
            errorMessage = "Couldn't crop that photo."
            return
        }
        cropState = nil
        uploading = true
        defer { uploading = false }
        let previousPath = AuthStore.shared.profileImagePath
        do {
            let storage = MediaStorageProvider.profileImages
            let filename = "\(UUID().uuidString.lowercased()).jpg"
            let ref = try await storage.upload(
                result.data,
                contentType: "image/jpeg",
                userId: userId,
                filename: filename
            )
            try await AuthStore.shared.updateProfileImagePath(ref.path)

            // Drop the old path's cached URL/image so any subsequent
            // ProfileAvatarImage with the new path goes through fresh.
            // Seed the new path's image cache directly with the bytes
            // we already have in hand — saves a round trip when the
            // avatar re-renders after upload.
            ProfileImageCache.shared.invalidate(path: previousPath)
            if let ui = UIImage(data: result.data) {
                ProfileImageCache.shared.cache(image: ui, for: ref.path)
            }

            errorMessage = nil
            pickerItem = nil
        } catch {
            log.error("Profile photo upload failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func cancelCrop() {
        cropState = nil
        pickerItem = nil
    }

    /// Removes the current profile photo from auth metadata. Storage
    /// cleanup is deferred to a future GC sweep (same lifecycle as
    /// orphaned background images).
    func clearPhoto() async {
        let previousPath = AuthStore.shared.profileImagePath
        do {
            try await AuthStore.shared.updateProfileImagePath(nil)
            ProfileImageCache.shared.invalidate(path: previousPath)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Reusable view modifier that presents the crop sheet for a
/// `ProfilePhotoPickerState`. Apply once per surface that drives the
/// upload (Profile onboarding page, future Settings → Profile screen).
struct ProfilePhotoCropSheet: ViewModifier {
    @Bindable var state: ProfilePhotoPickerState
    let userId: UUID?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: cropSheetBinding) { cropSheet }
    }

    private var cropSheetBinding: Binding<Bool> {
        Binding(
            get: { state.cropState != nil },
            set: { if !$0 { state.cancelCrop() } }
        )
    }

    @ViewBuilder
    private var cropSheet: some View {
        if let cropState = state.cropState {
            NavigationStack {
                PhotoCropView(state: cropState, circular: true)
                    .padding(.top, 8)
                    .navigationTitle("Crop photo")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { state.cancelCrop() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Use Photo") {
                                guard let userId else { return }
                                Task { await state.commitCrop(userId: userId) }
                            }
                            .fontWeight(.semibold)
                            .tint(Color.DS.sageDeep)
                            .disabled(userId == nil)
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

extension View {
    /// Convenience wrapper for `ProfilePhotoCropSheet`.
    func profilePhotoCropSheet(state: ProfilePhotoPickerState, userId: UUID?) -> some View {
        modifier(ProfilePhotoCropSheet(state: state, userId: userId))
    }
}
