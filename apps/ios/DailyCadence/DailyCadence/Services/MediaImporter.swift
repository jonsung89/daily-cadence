import Foundation
import UIKit
import AVFoundation
import ImageIO
import OSLog
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

    private static let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "MediaImporter")

    enum ImportError: Error {
        case loadFailed
        case unsupported
    }

    /// Re-encodes `data` as JPEG (q=0.85), resizing so the longest edge is
    /// at most `maxDimension` points.
    ///
    /// **Memory-efficient decode.** Uses `CGImageSourceCreateThumbnailAtIndex`,
    /// which decodes the source *directly to the target size* without ever
    /// holding the full-resolution decode in memory. That's the difference
    /// between handling a 48 MP iPhone Pro ProRAW (~187 MB fully decoded,
    /// jetsam territory) and the same image as a ~3 MB 2048-edge JPEG.
    ///
    /// Also applies EXIF orientation (`...WithTransform`), so the returned
    /// JPEG is already `.up`-oriented — downstream `normalizedUp()` will
    /// short-circuit instead of allocating another redraw buffer.
    static func downscale(_ data: Data, maxDimension: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            log.error("downscale: CGImageSourceCreateWithData failed for \(data.count) bytes")
            return nil
        }
        // Clamp the thumbnail target to the source's longest edge — the
        // thumbnail API treats `maxPixelSize` as a literal target and will
        // happily UPSCALE a small source up to it. Pixel dims bridge from
        // CFNumber as Int, not CGFloat; falling back to `maxDimension`
        // when properties are unreadable preserves the original behavior.
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let srcW = (props?[kCGImagePropertyPixelWidth] as? Int).map(CGFloat.init) ?? maxDimension
        let srcH = (props?[kCGImagePropertyPixelHeight] as? Int).map(CGFloat.init) ?? maxDimension
        let effectiveMax = min(maxDimension, max(srcW, srcH))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: effectiveMax,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            log.error("downscale: CGImageSourceCreateThumbnailAtIndex failed (max=\(Int(maxDimension)))")
            return nil
        }
        let img = UIImage(cgImage: thumb)
        log.debug("downscale: \(data.count) bytes → \(Int(img.size.width))×\(Int(img.size.height)) (max=\(Int(maxDimension)), src=\(Int(srcW))×\(Int(srcH)))")
        return img.jpegData(compressionQuality: 0.85)
    }

    /// Maximum longest-edge for stored media-note photos. Generous enough
    /// for the fullscreen `MediaViewerScreen` on iPhone Pro Max
    /// (1290×2796), still ~10× smaller than a 48 MP ProRAW.
    static let mediaNoteMaxDimension: CGFloat = 2048

    /// Loads the picker item's bytes, generates a poster + aspect ratio if
    /// it's a video, and returns a fully-formed `MediaPayload` ready to be
    /// stored on a `MockNote.Content.media`.
    static func makePayload(from item: PhotosPickerItem) async throws -> MediaPayload {
        // PhotosPickerItem.supportedContentTypes signals image vs video.
        // `.image` and `.movie` are the relevant UTType ids.
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        log.debug("makePayload: isVideo=\(isVideo) types=\(item.supportedContentTypes.map(\.identifier).joined(separator: ","))")

        guard let data = try await item.loadTransferable(type: Data.self) else {
            log.error("loadTransferable returned nil")
            throw ImportError.loadFailed
        }
        log.debug("loaded \(data.count) bytes (\(String(format: "%.1f", Double(data.count) / 1_048_576.0)) MB)")

        if isVideo {
            return try await videoPayload(from: data)
        } else {
            return try imagePayload(from: data)
        }
    }

    // MARK: - Image

    private static func imagePayload(from data: Data) throws -> MediaPayload {
        // Downscale via ImageIO BEFORE any full UIImage decode — a 48 MP
        // ProRAW would otherwise allocate ~187 MB just to compute aspect.
        // The thumbnail API peaks at the target size (a few MB) and also
        // bakes in EXIF orientation, so downstream consumers get an
        // already-`.up`-oriented JPEG.
        guard let downscaled = downscale(data, maxDimension: mediaNoteMaxDimension) else {
            log.error("imagePayload: downscale failed for \(data.count) bytes")
            throw ImportError.unsupported
        }
        guard let img = UIImage(data: downscaled) else {
            log.error("imagePayload: post-downscale UIImage(data:) failed")
            throw ImportError.unsupported
        }
        let mp = (img.size.width * img.size.height) / 1_000_000
        log.info("imagePayload stored: \(Int(img.size.width))×\(Int(img.size.height)) (\(String(format: "%.1f", mp)) MP) \(downscaled.count) bytes")
        let aspect = img.size.height > 0 ? img.size.width / img.size.height : 1.0
        return MediaPayload(
            kind: .image,
            data: downscaled,
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
