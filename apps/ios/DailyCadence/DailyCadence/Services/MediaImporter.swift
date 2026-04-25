import Foundation
import UIKit
import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Turns a `PhotosPickerItem` into a `MediaPayload` — handles the photo
/// vs video divergence (poster generation, aspect-ratio extraction, temp
/// file cleanup) so callers like `MediaNoteEditorScreen` can stay focused
/// on UI.
///
/// Phase E.3 ships an in-memory MVP — we hold the full asset's bytes in
/// the `MediaPayload`. Phase F+ swaps this for a Supabase Storage upload
/// pipeline; the importer's signature stays the same (caller still
/// receives a `MediaPayload`-shaped result), only the storage backing
/// changes.
enum MediaImporter {

    enum ImportError: Error {
        case loadFailed
        case unsupported
    }

    /// Loads the picker item's bytes, generates a poster + aspect ratio if
    /// it's a video, and returns a fully-formed `MediaPayload` ready to be
    /// stored on a `MockNote.Content.media`.
    static func makePayload(from item: PhotosPickerItem) async throws -> MediaPayload {
        // PhotosPickerItem.supportedContentTypes signals image vs video.
        // `.image` and `.movie` are the relevant UTType ids.
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }

        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw ImportError.loadFailed
        }

        if isVideo {
            return try await videoPayload(from: data)
        } else {
            return try imagePayload(from: data)
        }
    }

    // MARK: - Image

    private static func imagePayload(from data: Data) throws -> MediaPayload {
        guard let img = UIImage(data: data) else { throw ImportError.unsupported }
        let aspect = img.size.height > 0 ? img.size.width / img.size.height : 1.0
        return MediaPayload(
            kind: .image,
            data: data,
            posterData: nil,
            aspectRatio: aspect
        )
    }

    // MARK: - Video

    private static func videoPayload(from data: Data) async throws -> MediaPayload {
        // AVAsset reads from URL — write the bytes to a temp file just long
        // enough to extract the poster + tracks, then clean up. The bytes
        // we keep are the original `data` blob, not the temp file.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-import-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try data.write(to: tempURL)
        let asset = AVURLAsset(url: tempURL)

        let aspect = await videoAspectRatio(asset: asset) ?? (16.0 / 9.0)
        let posterData = await firstFramePosterData(asset: asset)

        return MediaPayload(
            kind: .video,
            data: data,
            posterData: posterData,
            aspectRatio: aspect
        )
    }

    private static func videoAspectRatio(asset: AVAsset) async -> CGFloat? {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let oriented = size.applying(transform)
            let w = abs(oriented.width)
            let h = abs(oriented.height)
            guard h > 0 else { return nil }
            return w / h
        } catch {
            return nil
        }
    }

    private static func firstFramePosterData(asset: AVAsset) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        do {
            // iOS 16+ async image API.
            let (cgImage, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85)
        } catch {
            return nil
        }
    }
}
