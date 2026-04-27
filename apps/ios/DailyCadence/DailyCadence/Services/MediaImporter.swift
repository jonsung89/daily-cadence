import Foundation
import UIKit
import AVFoundation
import CoreTransferable
import ImageIO
import OSLog
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// File-based handoff for video imports. The PhotosPicker hands us a
/// scoped URL to the original asset; we copy it to our own temp
/// location during the importing closure (fast disk-to-disk on iPhone
/// NVMe) and then own that copy.
///
/// **Why not `Data`.** `loadTransferable(type: Data.self)` materializes
/// the full asset in RAM before returning. For a ~70s ProRes / ProRAW
/// video that can be 1+ GB — minutes of stall on real hardware, OOM on
/// older devices. The file path stays on disk the whole time.
struct VideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("dc-import-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

/// Turns a `PhotosPickerItem` into a `MediaPayload` — handles the photo
/// vs video divergence (poster generation, aspect-ratio extraction, temp
/// file cleanup) so callers like `MediaNoteEditorScreen` can stay focused
/// on UI.
///
/// Phase F.1.1b' replaces the 60s "reject too-long videos" path with a
/// trim handoff: `makePayload(from:)` returns `ImportResult` — either a
/// finished `MediaPayload`, or a `VideoTrimSource` the caller hands to
/// `VideoTrimSheet`. After the user picks a range, the caller calls
/// `makeTrimmedVideoPayload(source:range:)` to finish the import.
enum MediaImporter {

    private static let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "MediaImporter")

    enum ImportError: Error, LocalizedError {
        case loadFailed
        case unsupported
        /// HEVC re-encode failed. Surfaced when the trim export fails;
        /// callers should show an error and let the user try again.
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .loadFailed:   return "Couldn't load that file."
            case .unsupported:  return "That file isn't supported."
            case .exportFailed: return "Couldn't process that video."
            }
        }
    }

    /// Outcome of `makePayload(from:)`. `.needsTrim` carries a temp file
    /// URL the caller must either pass to `makeTrimmedVideoPayload` or
    /// discard via `discardTrimSource(_:)` if the user cancels.
    enum ImportResult {
        case payload(MediaPayload)
        case needsTrim(VideoTrimSource)
    }

    /// Hand-off to `VideoTrimSheet` for a video longer than the cap.
    /// Owns the temp file written from the picker bytes; either
    /// `makeTrimmedVideoPayload` (success path) or `discardTrimSource`
    /// (cancel path) cleans it up. `Identifiable` so it can drive
    /// `.sheet(item:)`.
    struct VideoTrimSource: Identifiable {
        let id = UUID()
        let sourceURL: URL
        let duration: Double
        let aspectRatio: CGFloat
        let posterData: Data?
    }

    /// Maximum trimmed-video duration. Picked clips longer than this go
    /// through `VideoTrimSheet`, which initialises the trim window to
    /// the first `videoMaxDurationSeconds` of the source.
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

    /// Loads the picker item and returns either a finished payload or a
    /// `VideoTrimSource` the caller must route through `VideoTrimSheet`
    /// for clips over the duration cap.
    ///
    /// **Video path uses `VideoFile`** (file-based transferable), not
    /// `Data` — for ProRes / ProRAW assets that can run 1+ GB, the
    /// `Data` path stalls minutes on RAM materialization. File-based
    /// is a fast disk-to-disk copy.
    static func makePayload(from item: PhotosPickerItem) async throws -> ImportResult {
        // PhotosPickerItem.supportedContentTypes signals image vs video.
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        let t0 = Date()

        if isVideo {
            guard let movie = try await item.loadTransferable(type: VideoFile.self) else {
                log.error("loadTransferable(VideoFile) returned nil")
                throw ImportError.loadFailed
            }
            // File size + transferable elapsed give us a clear signal on
            // user devices: big elapsed + small file = transcoding;
            // big elapsed + big file = iCloud download; small elapsed = local.
            // `preferredItemEncoding: .current` at picker call sites
            // skips Apple's default H.264 transcode for ProRes / ProRAW.
            let bytes = (try? FileManager.default.attributesOfItem(atPath: movie.url.path)[.size] as? Int) ?? 0
            log.info("video import: \(String(format: "%.1f", Double(bytes) / 1_048_576.0))MB in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
            return try await videoImportResult(from: movie.url)
        } else {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                log.error("loadTransferable(Data) returned nil")
                throw ImportError.loadFailed
            }
            log.debug("image import: \(String(format: "%.1f", Double(data.count) / 1_048_576.0))MB in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
            return .payload(try imagePayload(from: data))
        }
    }

    /// Caller-side cleanup for the cancel path. Idempotent — safe to call
    /// even if the file was already removed by a successful trim export.
    static func discardTrimSource(_ source: VideoTrimSource) {
        try? FileManager.default.removeItem(at: source.sourceURL)
    }

    // MARK: - Camera capture (Phase F.1.1b'.camera)

    /// Camera-capture image variant. The camera hands us a `UIImage`
    /// (already decoded). Encode to JPEG at q=0.92 to preserve quality,
    /// then run the same `imagePayload` flow as picker imports — same
    /// downscale + dual-size HEIC re-encode as library imports.
    static func makePayload(fromCameraImage image: UIImage) throws -> ImportResult {
        guard let jpeg = image.jpegData(compressionQuality: 0.92) else {
            log.error("makePayload(fromCameraImage:): jpegData returned nil")
            throw ImportError.unsupported
        }
        return .payload(try imagePayload(from: jpeg))
    }

    /// Camera-capture video variant. The picker hands us a `URL` we
    /// already own (`CameraPicker` copies it into our temp dir before
    /// the picker tears down). Routes through the same
    /// `videoImportResult` pipeline as library imports, so >60s
    /// captures land in `VideoTrimSheet` automatically — same trim UX
    /// the user gets for picker imports.
    static func makePayload(fromCameraVideoURL url: URL) async throws -> ImportResult {
        try await videoImportResult(from: url)
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

    private static func videoImportResult(from sourceURL: URL) async throws -> ImportResult {
        // sourceURL is a temp file we own (copied by VideoFile's
        // FileRepresentation). Two outcomes:
        //   - duration ≤ cap: re-encode HEVC inline, generate poster,
        //     clean up source URL, return payload.
        //   - duration > cap: hand the URL to VideoTrimSheet via
        //     VideoTrimSource — the sheet's confirm/cancel path owns
        //     cleanup. **Skip upfront poster generation** in this
        //     branch — `makeTrimmedVideoPayload` regenerates from the
        //     new start frame, and a full ProRes frame decode here
        //     would just slow the trim sheet's appearance.
        let asset = AVURLAsset(url: sourceURL)

        let duration = try? await asset.load(.duration)
        let seconds = duration?.seconds ?? 0
        let aspect = await videoAspectRatio(asset: asset) ?? (16.0 / 9.0)

        if seconds > videoMaxDurationSeconds {
            log.info("video > cap (\(String(format: "%.1f", seconds))s) — handing off to trim sheet")
            return .needsTrim(VideoTrimSource(
                sourceURL: sourceURL,
                duration: seconds,
                aspectRatio: aspect,
                posterData: nil
            ))
        }

        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let posterData = await firstFramePosterData(asset: asset)
        let encodedData: Data? = await reencodeHEVC(asset: asset, range: nil)

        guard let encodedData else {
            log.error("HEVC re-encode failed for under-cap video")
            throw ImportError.exportFailed
        }

        log.info("videoImportResult: \(seconds)s aspect=\(String(format: "%.2f", aspect)) hevc=\(encodedData.count)")

        return .payload(MediaPayload(
            kind: .video,
            data: encodedData,
            posterData: posterData,
            thumbnailData: nil,
            aspectRatio: aspect
        ))
    }

    /// Trim-sheet success path. Re-encodes the source HEVC restricted to
    /// `range`, regenerates the poster from the new start frame, and
    /// cleans up the temp source URL. Throws `.exportFailed` if the
    /// trimmed export doesn't produce bytes — for trim there's no honest
    /// fallback (the original would still be too long).
    static func makeTrimmedVideoPayload(
        source: VideoTrimSource,
        range: CMTimeRange
    ) async throws -> MediaPayload {
        defer { try? FileManager.default.removeItem(at: source.sourceURL) }

        let asset = AVURLAsset(url: source.sourceURL)
        let trimmedPoster = await frameJPEGData(asset: asset, at: range.start) ?? source.posterData

        guard let encodedData = await reencodeHEVC(asset: asset, range: range) else {
            log.error("Trimmed HEVC re-encode failed")
            throw ImportError.exportFailed
        }

        let trimmedSeconds = range.duration.seconds
        log.info("makeTrimmedVideoPayload: trimmed=\(trimmedSeconds)s hevc=\(encodedData.count)")

        return MediaPayload(
            kind: .video,
            data: encodedData,
            posterData: trimmedPoster,
            thumbnailData: nil,
            aspectRatio: source.aspectRatio
        )
    }

    /// Re-encodes the asset to HEVC at 1080p max, optionally restricted
    /// to `range`. Returns the encoded bytes, or `nil` if export failed.
    private static func reencodeHEVC(asset: AVURLAsset, range: CMTimeRange?) async -> Data? {
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
        if let range { session.timeRange = range }

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
        await frameJPEGData(asset: asset, at: .zero)
    }

    /// Returns a JPEG-encoded poster for the frame nearest `time`. Used
    /// by `firstFramePosterData` and by the trim path to refresh the
    /// poster after the user picks a non-zero start.
    static func frameJPEGData(asset: AVAsset, at time: CMTime) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        do {
            // iOS 16+ async image API.
            let (cgImage, _) = try await generator.image(at: time)
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85)
        } catch {
            return nil
        }
    }
}
