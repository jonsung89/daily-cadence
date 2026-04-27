import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Bridges `UIImagePickerController(.camera)` into SwiftUI for the
/// "Take Photo or Video" path. The system `PhotosPicker` is library-only
/// and doesn't expose the camera; `UIImagePickerController` is still the
/// canonical capture surface (Apple's deprecation note has stood for
/// years without a replacement). Apple Mail and Notes both still use it.
///
/// Reports back via `onPick`: an `.image(UIImage)` for stills,
/// `.video(URL)` for clips (the URL points to a temp copy we own — the
/// picker's own URL is invalidated once it dismisses), or `nil` on
/// cancel. The caller is responsible for dismissing the SwiftUI sheet
/// in response.
struct CameraPicker: UIViewControllerRepresentable {
    enum Capture {
        case image(UIImage)
        case video(URL)
    }

    let onPick: (Capture?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        // Both photo and video — the picker's native UI exposes the
        // mode switcher when more than one type is allowed.
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.cameraCaptureMode = .photo
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Video takes priority — for video captures, the picker
            // also returns an `originalImage` (the first-frame poster);
            // the URL is what we want.
            if let mediaURL = info[.mediaURL] as? URL {
                // The picker's URL lives in its own temp scope and
                // disappears once the picker dismisses. Copy to our
                // own temp file so the URL stays valid through the
                // import pipeline (HEVC re-encode + poster generation).
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("dc-camera-\(UUID().uuidString).mov")
                do {
                    try FileManager.default.copyItem(at: mediaURL, to: dest)
                    parent.onPick(.video(dest))
                } catch {
                    parent.onPick(nil)
                }
            } else if let image = info[.originalImage] as? UIImage {
                parent.onPick(.image(image))
            } else {
                parent.onPick(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onPick(nil)
        }
    }
}
