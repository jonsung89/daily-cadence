import Foundation
import Testing
import UIKit
@testable import DailyCadence

/// Phase D.2.2 — covers `MediaImporter.downscale(_:maxDimension:)`, the
/// re-encode helper that keeps `ImageBackground.imageData` bounded so a
/// camera-roll HEIC doesn't sit full-size in a card slot.
struct MediaImporterTests {

    /// Renders a solid-color image at the given pixel size and returns
    /// its PNG bytes. PNG (not JPEG) so the source bytes have predictable
    /// dimensions independent of the encoder's compression heuristics.
    /// `scale = 1` so the logical size IS the pixel size — without this
    /// the simulator's 3× scale would emit an 1800×1200 PNG for a
    /// 600×400 logical request.
    private static func renderPNG(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let img = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return img.pngData() ?? Data()
    }

    @Test func downscaleShrinksLandscapeToMaxDimensionOnLongEdge() {
        let source = Self.renderPNG(width: 4032, height: 3024)
        guard let result = MediaImporter.downscale(source, maxDimension: 1024) else {
            Issue.record("downscale returned nil for a valid image")
            return
        }
        guard let resized = UIImage(data: result) else {
            Issue.record("downscale produced bytes that don't decode")
            return
        }
        // Longest edge clamped, aspect preserved.
        #expect(max(resized.size.width, resized.size.height) <= 1024)
        let aspect = resized.size.width / resized.size.height
        #expect(abs(aspect - (4032.0 / 3024.0)) < 0.01)
    }

    @Test func downscaleShrinksPortraitToMaxDimensionOnLongEdge() {
        let source = Self.renderPNG(width: 1080, height: 1920)
        guard let result = MediaImporter.downscale(source, maxDimension: 1024),
              let resized = UIImage(data: result) else {
            Issue.record("downscale failed for portrait image")
            return
        }
        #expect(max(resized.size.width, resized.size.height) <= 1024)
        // 1080×1920 → 576×1024
        #expect(Int(resized.size.height.rounded()) == 1024)
    }

    @Test func downscaleLeavesAlreadySmallImageWithinBounds() {
        // Already smaller than max — output should stay within bounds
        // (re-encoded as JPEG, but never upscaled).
        let source = Self.renderPNG(width: 600, height: 400)
        guard let result = MediaImporter.downscale(source, maxDimension: 1024),
              let resized = UIImage(data: result) else {
            Issue.record("downscale failed for small image")
            return
        }
        #expect(resized.size.width <= 600 + 1)
        #expect(resized.size.height <= 400 + 1)
    }

    @Test func downscaleProducesJPEGNotPNG() {
        // Output must be JPEG so the size invariant (1024 max longest
        // edge → ~150-250 KB) holds regardless of source format.
        let source = Self.renderPNG(width: 2000, height: 2000)
        guard let result = MediaImporter.downscale(source, maxDimension: 1024) else {
            Issue.record("downscale returned nil")
            return
        }
        // JPEG magic bytes: FF D8 FF
        #expect(result.count >= 3)
        #expect(result[0] == 0xFF)
        #expect(result[1] == 0xD8)
        #expect(result[2] == 0xFF)
    }

    @Test func downscaleRejectsInvalidData() {
        let bogus = Data([0x00, 0x01, 0x02, 0x03])
        let result = MediaImporter.downscale(bogus, maxDimension: 1024)
        #expect(result == nil)
    }
}
