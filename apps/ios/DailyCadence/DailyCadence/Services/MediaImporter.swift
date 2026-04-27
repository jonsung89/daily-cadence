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

    enum ImportError: Error, LocalizedError {
        case loadFailed
        case unsupported
        /// Phase F.1.1b — picked video exceeds the 60s cap. F.1.1b' will
        /// add a trim sheet; for now we surface this so the editor can
        /// show a clear error rather than silently chopping the video.
        case videoTooLong(seconds: Double)
        /// HEVC re-encode failed. Falls back to the original bytes.
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .loadFailed:               return "Couldn't load that file."
            case .unsupported:              return "That file isn't supported."
            case .videoTooLong(let s):
                return "Videos must be 60 seconds or shorter (yours is \(Int(s.rounded()))s). A trim tool is coming soon."
            case .exportFailed:             return "Couldn't process that video."
            }
        }
    }

    /// Maximum video duration in seconds. Beyond this we reject the import
    /// (F.1.1b' will add a trim sheet that offers to slice to the first
    /// `videoMaxDurationSeconds` instead of rejecting outright).
    static let videoMaxDurationSeconds: Double = 60

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

    /// Phase F.1.1b — small thumbnail dimension for image cards. Cards
    /// in the 2-col masonry render at ~180-200pt wide, so 600px is
    /// plenty for retina (3×) sharpness. Cuts grid-view egress 5-10×.
    static let mediaNoteThumbnailDimension: CGFloat = 600

    /// Phase F.1.1b — encodes a `UIImage` as HEIC with the given quality.
    /// HEIC is ~50% smaller than JPEG at perceptually-equivalent quality.
    /// All supported devices (iOS 26 minimum) encode HEIC natively via
    /// ImageIO. Falls back to nil on encode failure; callers should use
    /// the JPEG bytes from `downscale` as a fallback.
    static func encodeHEIC(_ image: UIImage, quality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

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
        // Phase F.1.1b — produce dual-size HEIC.
        // Full: 2048px max longest edge, HEIC q=0.85 (~150-300 KB typical).
        // Thumb: 600px max longest edge, HEIC q=0.7 (~30-60 KB).
        // HEIC encode falls back to JPEG bytes if it ever fails; old
        // devices aren't a concern at our iOS 26 minimum.
        guard let fullJPEG = downscale(data, maxDimension: mediaNoteMaxDimension),
              let fullImage = UIImage(data: fullJPEG) else {
            log.error("imagePayload: full-size downscale failed for \(data.count) bytes")
            throw ImportError.unsupported
        }
        let fullHEIC = encodeHEIC(fullImage, quality: 0.85) ?? fullJPEG

        let thumbJPEG = downscale(data, maxDimension: mediaNoteThumbnailDimension)
        let thumbHEIC: Data? = thumbJPEG.flatMap { jpeg in
            guard let img = UIImage(data: jpeg) else { return nil }
            return encodeHEIC(img, quality: 0.7) ?? jpeg
        }

        let mp = (fullImage.size.width * fullImage.size.height) / 1_000_000
        log.info("imagePayload: \(Int(fullImage.size.width))×\(Int(fullImage.size.height)) (\(String(format: "%.1f", mp))MP) full=\(fullHEIC.count) thumb=\(thumbHEIC?.count ?? 0)")
        let aspect = fullImage.size.height > 0 ? fullImage.size.width / fullImage.size.height : 1.0
        return MediaPayload(
            kind: .image,
            data: fullHEIC,
            posterData: nil,
            thumbnailData: thumbHEIC,
            aspectRatio: aspect
        )
    }

    // MARK: - Video

    private static func videoPayload(from data: Data) async throws -> MediaPayload {
        // Phase F.1.1b — re-encode source to HEVC 1080p (~50% smaller than
        // H.264 at same perceived quality). Reject videos longer than the
        // 60s cap (F.1.1b' will add a trim sheet). Fallback strategy: if
        // re-encode fails for any reason, ship the original bytes.
        let tempInputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-import-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: tempInputURL) }
        try data.write(to: tempInputURL)
        let asset = AVURLAsset(url: tempInputURL)

        // Length cap. Reject early so we don't waste CPU on the export.
        let duration = try? await asset.load(.duration)
        let seconds = duration?.seconds ?? 0
        guard seconds <= videoMaxDurationSeconds else {
            log.notice("Rejecting video: \(seconds)s exceeds \(videoMaxDurationSeconds)s cap")
            throw ImportError.videoTooLong(seconds: seconds)
        }

        let aspect = await videoAspectRatio(asset: asset) ?? (16.0 / 9.0)
        let posterData = await firstFramePosterData(asset: asset)

        // Re-encode to HEVC 1080p. The 1920x1080 preset adapts the
        // source to fit within those bounds (no upscaling).
        let encodedData: Data = await reencodeHEVC(asset: asset) ?? {
            log.warning("HEVC re-encode failed, shipping original bytes (\(data.count) bytes)")
            return data
        }()

        log.info("videoPayload: \(seconds)s aspect=\(String(format: "%.2f", aspect)) original=\(data.count) hevc=\(encodedData.count)")

        return MediaPayload(
            kind: .video,
            data: encodedData,
            posterData: posterData,
            thumbnailData: nil,
            aspectRatio: aspect
        )
    }

    /// Re-encodes the asset to HEVC at 1080p max. Returns the encoded
    /// bytes, or `nil` if export failed.
    private static func reencodeHEVC(asset: AVURLAsset) async -> Data? {
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHEVC1920x1080
        ) else {
            log.error("AVAssetExportSession init failed (HEVC 1080p preset)")
            return nil
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-export-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        do {
            // iOS 18+ async export API.
            try await session.export(to: outputURL, as: .mp4)
            return try Data(contentsOf: outputURL)
        } catch {
            log.error("HEVC export failed: \(error.localizedDescription)")
            return nil
        }
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
