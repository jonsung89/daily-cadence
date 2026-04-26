import SwiftUI
import UIKit
import OSLog

private let cropLog = Logger(subsystem: "com.jonsung.DailyCadence", category: "PhotoCrop")

/// Aspect ratio choices for the crop tool. `Free` means the user can
/// shape the crop rectangle however they like by dragging corners.
enum PhotoCropAspect: String, CaseIterable, Identifiable {
    case free
    case square
    case fourThree   // 4:3, landscape
    case threeFour   // 3:4, portrait
    case sixteenNine // 16:9, landscape
    case nineSixteen // 9:16, portrait

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free:        return "Free"
        case .square:      return "1:1"
        case .fourThree:   return "4:3"
        case .threeFour:   return "3:4"
        case .sixteenNine: return "16:9"
        case .nineSixteen: return "9:16"
        }
    }

    /// Returns the explicit aspect ratio (width/height) or `nil` for `.free`.
    var ratio: CGFloat? {
        switch self {
        case .free:        return nil
        case .square:      return 1.0
        case .fourThree:   return 4.0 / 3.0
        case .threeFour:   return 3.0 / 4.0
        case .sixteenNine: return 16.0 / 9.0
        case .nineSixteen: return 9.0 / 16.0
        }
    }
}

/// Photos.app-style crop UX.
///
/// **Model.** The image lays out at scale-to-fit inside the canvas
/// (`imageRect`) and can additionally be **scaled** (pinch) and
/// **panned** (drag inside the rect interior) — those modify
/// `imageScale` and `imageOffset`. The displayed image at any time is
/// `displayedImageRect`, which is `imageRect` with the transform
/// applied. A **crop rectangle** floats on top in canvas coordinates;
/// corner handles resize it. Areas outside the crop are dimmed via an
/// eo-fill `Canvas` mask. Aspect chips constrain the crop's shape.
///
/// **Gesture map.**
/// - Drag a corner handle → resize the crop rect (aspect-locked when a
///   ratio chip is active).
/// - Drag inside the crop rect → pan the image under the rect (Apple
///   Photos pattern — the rect doesn't move, the image does).
/// - Pinch → zoom the image (1×–5×). At 1× the offset clamps back to
///   center; at higher scales the offset is clamped so the displayed
///   image always covers the base `imageRect`.
/// - Aspect chip → resets zoom + pan and re-fits the crop to the
///   chosen ratio.
@Observable
final class PhotoCropState {
    let original: UIImage

    var aspect: PhotoCropAspect = .free {
        didSet {
            // When the aspect chip changes, reset the image transform and
            // re-center the crop rect inside the base image rect. Mixing
            // aspect changes with stale zoom/pan state reads as a bug;
            // resetting matches Apple Photos' behavior.
            imageScale = 1.0
            imageOffset = .zero
            cropRect = aspectFittedCropRect(in: imageRect)
        }
    }

    /// Where the source image lays out inside the canvas at scale-to-fit
    /// (canvas coordinates). The "base" rect — `displayedImageRect`
    /// applies the user's pinch/pan on top.
    private(set) var imageRect: CGRect = .zero

    /// The crop rectangle in canvas coordinates — what the dimmed
    /// overlay punches a hole through.
    var cropRect: CGRect = .zero

    /// Image zoom factor. 1.0 = scale-to-fit. Range 1.0...5.0 (1× floor
    /// keeps the source visible inside the crop area; 5× cap is enough
    /// for any realistic crop-into-detail need without making the image
    /// effectively unmovable).
    var imageScale: CGFloat = 1.0

    /// Image pan offset, in canvas points, applied on top of the
    /// scale-to-fit position. Clamped on every update so the displayed
    /// image always covers `imageRect`.
    var imageOffset: CGSize = .zero

    /// `imageRect` with the user's pinch + pan applied — the rect the
    /// image actually occupies onscreen. `commitCrop` maps `cropRect`
    /// back to source pixels through this rect.
    var displayedImageRect: CGRect {
        let w = imageRect.width * imageScale
        let h = imageRect.height * imageScale
        let cx = imageRect.midX + imageOffset.width
        let cy = imageRect.midY + imageOffset.height
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// Clamps a proposed `(scale, offset)` so the displayed image always
    /// covers the base `imageRect` (no exposed canvas chrome behind a
    /// panned-too-far image). Returns the clamped offset.
    func clampedOffset(_ proposed: CGSize, for scale: CGFloat) -> CGSize {
        let maxX = imageRect.width  * (scale - 1) / 2
        let maxY = imageRect.height * (scale - 1) / 2
        return CGSize(
            width:  max(-maxX, min(proposed.width,  maxX)),
            height: max(-maxY, min(proposed.height, maxY))
        )
    }

    init?(data: Data) {
        cropLog.debug("PhotoCropState.init: \(data.count) bytes")
        guard let raw = UIImage(data: data) else {
            cropLog.error("PhotoCropState.init: UIImage(data:) returned nil for \(data.count) bytes")
            return nil
        }
        let mp = (raw.size.width * raw.size.height) / 1_000_000
        cropLog.info("PhotoCropState.init decoded: \(Int(raw.size.width))×\(Int(raw.size.height)) (\(String(format: "%.1f", mp)) MP) orientation=\(raw.imageOrientation.rawValue)")
        self.original = raw.normalizedUp()
    }

    /// Called by `PhotoCropView` after measuring the canvas. Recomputes
    /// the visible image rect at scale-to-fit and re-fits the crop rect
    /// inside it. A canvas resize also resets the image transform — the
    /// previous zoom/pan was relative to the old rect and would be
    /// disorienting if carried into the new layout.
    func setImageRect(_ rect: CGRect) {
        let didChange = rect != imageRect
        imageRect = rect
        if cropRect == .zero || didChange {
            imageScale = 1.0
            imageOffset = .zero
            cropRect = aspectFittedCropRect(in: rect)
        }
    }

    /// Center-fitted crop rect inside `container`, sized to the chosen
    /// aspect (or filling `container` for `.free`).
    private func aspectFittedCropRect(in container: CGRect) -> CGRect {
        guard container.width > 0, container.height > 0 else { return container }
        guard let ratio = aspect.ratio else { return container }
        let containerRatio = container.width / container.height
        let w: CGFloat
        let h: CGFloat
        if ratio > containerRatio {
            // crop is wider than container → width-limited
            w = container.width
            h = w / ratio
        } else {
            h = container.height
            w = h * ratio
        }
        return CGRect(
            x: container.midX - w / 2,
            y: container.midY - h / 2,
            width: w,
            height: h
        )
    }

    // MARK: - Commit crop

    func commitCrop() -> (data: Data, aspectRatio: CGFloat)? {
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }
        guard let cg = original.cgImage else { return nil }

        let imageW = CGFloat(cg.width)
        let imageH = CGFloat(cg.height)

        // Map crop rect (canvas coords) → source image pixel coords
        // through `displayedImageRect`, which folds in the user's pinch
        // + pan transform. At zoom = 1, offset = 0 this collapses to the
        // original (cropRect / imageRect) mapping.
        let displayed = displayedImageRect
        let scaleX = imageW / displayed.width
        let scaleY = imageH / displayed.height
        var x = (cropRect.minX - displayed.minX) * scaleX
        var y = (cropRect.minY - displayed.minY) * scaleY
        var w = cropRect.width * scaleX
        var h = cropRect.height * scaleY

        // Defensive clamp — gesture handler keeps the crop inside imageRect,
        // but rounding errors can leak a fraction of a pixel out.
        if x < 0 { w += x; x = 0 }
        if y < 0 { h += y; y = 0 }
        if x + w > imageW { w = imageW - x }
        if y + h > imageH { h = imageH - y }
        guard w > 1, h > 1 else { return nil }

        let cropPx = CGRect(x: x, y: y, width: w, height: h).integral
        guard let cropped = cg.cropping(to: cropPx) else { return nil }
        let ui = UIImage(cgImage: cropped, scale: original.scale, orientation: .up)
        guard let data = ui.jpegData(compressionQuality: 0.9) else { return nil }
        return (data, cropPx.width / cropPx.height)
    }
}

/// SwiftUI surface for `PhotoCropState`.
struct PhotoCropView: View {
    @Bindable var state: PhotoCropState

    /// Crop rect at the moment a corner drag began. Snapshotted so the
    /// in-flight `DragGesture.translation` always applies to a stable
    /// starting rect rather than the live `cropRect` (which would
    /// compound the same translation every frame).
    @State private var dragStartRect: CGRect = .zero

    /// Image-pan offset at the moment a pan drag began. Same compounding
    /// concern as `dragStartRect` — we want translation applied against
    /// a stable origin.
    @State private var panStartOffset: CGSize? = nil

    /// Image scale at the moment a pinch began. `MagnifyGesture.value`
    /// reports the *cumulative* magnification for the gesture, so we
    /// multiply against this snapshot rather than against the live
    /// `imageScale`.
    @State private var pinchStartScale: CGFloat? = nil

    /// Minimum crop dimension in canvas coords. Below this the crop can
    /// be hard to grab and the resulting image is too small to be useful.
    private let minCropDimension: CGFloat = 60

    /// Hit area for each corner handle. The visible square is smaller —
    /// this is just the touch target.
    private let handleHitSize: CGFloat = 36

    /// Zoom range. 1× floor keeps the source visible inside the rect;
    /// 5× ceiling is enough for crop-into-detail without making the
    /// image effectively unmovable at extreme magnification.
    private let minImageScale: CGFloat = 1.0
    private let maxImageScale: CGFloat = 5.0

    var body: some View {
        VStack(spacing: 12) {
            cropCanvas
                .frame(maxWidth: .infinity)
                .frame(height: 360)
            aspectRow
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Crop canvas

    private var cropCanvas: some View {
        GeometryReader { geo in
            let imageRect = computeImageRect(in: geo.size)
            ZStack {
                Color.black.opacity(0.04)

                // Image scaled-to-fit at the computed rect, then
                // pinch-zoomed (`scaleEffect`) and panned (`offset`)
                // around its center. `commitCrop` reads the same
                // transform off `state.displayedImageRect`.
                Image(uiImage: state.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .scaleEffect(state.imageScale, anchor: .center)
                    .offset(state.imageOffset)
                    .position(x: imageRect.midX, y: imageRect.midY)

                // Dim outside the crop rect using even-odd fill.
                dimOverlay(canvas: geo.size)

                // Crop rect outline + handles + image-pan area.
                cropFrame(imageRect: imageRect)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            // Pinch is two-finger; coexists naturally with the
            // single-finger drags on handles and the rect interior.
            .gesture(magnifyGesture())
            .onAppear { state.setImageRect(imageRect) }
            .onChange(of: imageRect) { _, new in state.setImageRect(new) }
        }
    }

    private func computeImageRect(in canvas: CGSize) -> CGRect {
        let imageSize = state.original.size
        guard imageSize.width > 0, imageSize.height > 0,
              canvas.width > 0, canvas.height > 0 else { return .zero }
        let scale = min(canvas.width / imageSize.width, canvas.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        let x = (canvas.width - w) / 2
        let y = (canvas.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Dim overlay

    private func dimOverlay(canvas: CGSize) -> some View {
        let r = state.cropRect
        return Canvas { ctx, size in
            var path = Path(CGRect(origin: .zero, size: size))
            path.addRect(r)
            ctx.fill(path, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
        }
        .frame(width: canvas.width, height: canvas.height)
        .allowsHitTesting(false)
    }

    // MARK: - Crop frame (border + handles + image-pan area)

    private func cropFrame(imageRect: CGRect) -> some View {
        let r = state.cropRect
        return ZStack {
            // White outline border around the crop rect.
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .allowsHitTesting(false)

            // Thirds guide for visual alignment.
            ThirdsGuides()
                .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .allowsHitTesting(false)

            // Image-pan area — invisible rectangle inside the crop rect,
            // shrunk so it doesn't overlap the corner hit zones. Single-
            // finger drag inside this area pans the *image* under the
            // rect (Apple Photos pattern — the rect is fixed, the image
            // moves).
            let centerInset = handleHitSize / 2
            let centerW = max(0, r.width - centerInset * 2)
            let centerH = max(0, r.height - centerInset * 2)
            if centerW > 0, centerH > 0 {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: centerW, height: centerH)
                    .position(x: r.midX, y: r.midY)
                    .contentShape(Rectangle())
                    .gesture(imagePanGesture())
            }

            // Four corner handles.
            cornerHandle(at: .topLeft,     position: CGPoint(x: r.minX, y: r.minY), imageRect: imageRect)
            cornerHandle(at: .topRight,    position: CGPoint(x: r.maxX, y: r.minY), imageRect: imageRect)
            cornerHandle(at: .bottomLeft,  position: CGPoint(x: r.minX, y: r.maxY), imageRect: imageRect)
            cornerHandle(at: .bottomRight, position: CGPoint(x: r.maxX, y: r.maxY), imageRect: imageRect)
        }
    }

    private func cornerHandle(at corner: Corner, position: CGPoint, imageRect: CGRect) -> some View {
        // Offset the visible glyph 9pt inward so its OUTER corner lands
        // on the crop-rect corner with the arms pointing into the rect.
        // Without this, the glyph centers on the corner — half the L
        // renders outside the rect, and when the crop equals the image
        // bounds at a canvas edge the outer half gets clipped by the
        // canvas's `.clipped()`. Hit zone stays centered for a generous
        // touch target.
        let glyphInset: CGFloat = 9
        let glyphOffset: CGSize = {
            switch corner {
            case .topLeft:     return CGSize(width:  glyphInset, height:  glyphInset)
            case .topRight:    return CGSize(width: -glyphInset, height:  glyphInset)
            case .bottomLeft:  return CGSize(width:  glyphInset, height: -glyphInset)
            case .bottomRight: return CGSize(width: -glyphInset, height: -glyphInset)
            }
        }()
        return ZStack {
            // Larger transparent hit area, centered on the corner.
            Color.clear.frame(width: handleHitSize, height: handleHitSize)
            // Visible glyph: an L-shape that hugs the corner from inside.
            CornerGlyph(corner: corner)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .square))
                .frame(width: 18, height: 18)
                .offset(glyphOffset)
        }
        .contentShape(Rectangle())
        .position(position)
        .gesture(cornerDragGesture(corner: corner, imageRect: imageRect))
    }

    // MARK: - Gestures

    private func cornerDragGesture(corner: Corner, imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragStartRect == .zero { dragStartRect = state.cropRect }
                state.cropRect = applyCornerDrag(
                    corner: corner,
                    translation: drag.translation,
                    starting: dragStartRect,
                    in: imageRect
                )
            }
            .onEnded { _ in dragStartRect = .zero }
    }

    /// Single-finger drag inside the crop rect interior. Pans the
    /// *image* (not the rect) — Apple Photos pattern. Translation is
    /// clamped so the displayed image always covers the base
    /// `imageRect`.
    private func imagePanGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if panStartOffset == nil { panStartOffset = state.imageOffset }
                let proposed = CGSize(
                    width:  panStartOffset!.width  + drag.translation.width,
                    height: panStartOffset!.height + drag.translation.height
                )
                state.imageOffset = state.clampedOffset(proposed, for: state.imageScale)
            }
            .onEnded { _ in panStartOffset = nil }
    }

    /// Two-finger pinch on the canvas. Zooms the image in place around
    /// its center; clamped to `[minImageScale, maxImageScale]`. The
    /// existing offset is re-clamped against the new scale so a pinch-
    /// out from a panned position doesn't expose canvas chrome.
    private func magnifyGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchStartScale ?? state.imageScale
                if pinchStartScale == nil { pinchStartScale = base }
                let proposed = base * value.magnification
                let clamped = max(minImageScale, min(maxImageScale, proposed))
                state.imageScale = clamped
                state.imageOffset = state.clampedOffset(state.imageOffset, for: clamped)
            }
            .onEnded { _ in pinchStartScale = nil }
    }

    // MARK: - Resize math

    private func applyCornerDrag(
        corner: Corner,
        translation: CGSize,
        starting: CGRect,
        in imageRect: CGRect
    ) -> CGRect {
        var rect = starting
        switch corner {
        case .topLeft:
            rect.origin.x += translation.width
            rect.origin.y += translation.height
            rect.size.width -= translation.width
            rect.size.height -= translation.height
        case .topRight:
            rect.origin.y += translation.height
            rect.size.width += translation.width
            rect.size.height -= translation.height
        case .bottomLeft:
            rect.origin.x += translation.width
            rect.size.width -= translation.width
            rect.size.height += translation.height
        case .bottomRight:
            rect.size.width += translation.width
            rect.size.height += translation.height
        }

        // Aspect lock — when active, force the moving edges to maintain
        // ratio. We anchor on the corner OPPOSITE the one the user is
        // dragging and pick whichever dimension grew more, then derive
        // the other from the locked ratio.
        if let ratio = state.aspect.ratio {
            let anchor = anchorPoint(opposite: corner, of: starting)
            let proposedW = abs(rect.size.width)
            let proposedH = abs(rect.size.height)
            let useWidth = proposedW > proposedH * ratio
            let w = useWidth ? proposedW : proposedH * ratio
            let h = useWidth ? proposedW / ratio : proposedH
            rect = aspectAnchoredRect(width: w, height: h, anchor: anchor, corner: corner)
        }

        // Enforce minimum size before clamping position so we don't end up
        // with zero-size or negative-size rects.
        if rect.size.width < minCropDimension {
            // Push the moving edge back so the crop keeps the minimum width
            // anchored to the opposite edge.
            let delta = minCropDimension - rect.size.width
            switch corner {
            case .topLeft, .bottomLeft: rect.origin.x -= delta
            case .topRight, .bottomRight: break
            }
            rect.size.width = minCropDimension
        }
        if rect.size.height < minCropDimension {
            let delta = minCropDimension - rect.size.height
            switch corner {
            case .topLeft, .topRight: rect.origin.y -= delta
            case .bottomLeft, .bottomRight: break
            }
            rect.size.height = minCropDimension
        }

        return clampInsideImage(rect, in: imageRect)
    }

    private func anchorPoint(opposite corner: Corner, of rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:     return CGPoint(x: rect.maxX, y: rect.maxY)
        case .topRight:    return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomLeft:  return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.minX, y: rect.minY)
        }
    }

    private func aspectAnchoredRect(width w: CGFloat, height h: CGFloat, anchor: CGPoint, corner: Corner) -> CGRect {
        switch corner {
        case .topLeft:     return CGRect(x: anchor.x - w, y: anchor.y - h, width: w, height: h)
        case .topRight:    return CGRect(x: anchor.x,     y: anchor.y - h, width: w, height: h)
        case .bottomLeft:  return CGRect(x: anchor.x - w, y: anchor.y,     width: w, height: h)
        case .bottomRight: return CGRect(x: anchor.x,     y: anchor.y,     width: w, height: h)
        }
    }

    private func clampInsideImage(_ proposed: CGRect, in container: CGRect) -> CGRect {
        var rect = proposed
        // Clamp size first
        rect.size.width = min(rect.size.width, container.width)
        rect.size.height = min(rect.size.height, container.height)
        // Then clamp origin so the rect stays inside container.
        rect.origin.x = max(container.minX, min(rect.origin.x, container.maxX - rect.size.width))
        rect.origin.y = max(container.minY, min(rect.origin.y, container.maxY - rect.size.height))
        return rect
    }

    // MARK: - Aspect chips

    private var aspectRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PhotoCropAspect.allCases) { choice in
                    aspectChip(choice)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func aspectChip(_ choice: PhotoCropAspect) -> some View {
        let isSelected = state.aspect == choice
        return Button {
            state.aspect = choice
        } label: {
            Text(choice.label)
                .font(.DS.sans(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.DS.bg2 : Color.DS.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.DS.ink : Color.DS.bg1)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.clear : Color.DS.border1,
                            lineWidth: 0.5
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aspect \(choice.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Corner enum + glyph shapes

private enum Corner {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// L-shaped path for a corner handle, hugging the appropriate corner
/// of an 18×18 frame.
private struct CornerGlyph: Shape {
    let corner: Corner

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        switch corner {
        case .topLeft:
            p.move(to: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: w, y: 0))
        case .topRight:
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: w, y: 0))
            p.addLine(to: CGPoint(x: w, y: h))
        case .bottomLeft:
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: w, y: h))
        case .bottomRight:
            p.move(to: CGPoint(x: w, y: 0))
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
        }
        return p
    }
}

/// Rule-of-thirds guide: two horizontal + two vertical lines at 1/3 and
/// 2/3 of the rect.
private struct ThirdsGuides: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // Vertical
        p.move(to: CGPoint(x: w / 3, y: 0))
        p.addLine(to: CGPoint(x: w / 3, y: h))
        p.move(to: CGPoint(x: 2 * w / 3, y: 0))
        p.addLine(to: CGPoint(x: 2 * w / 3, y: h))
        // Horizontal
        p.move(to: CGPoint(x: 0, y: h / 3))
        p.addLine(to: CGPoint(x: w, y: h / 3))
        p.move(to: CGPoint(x: 0, y: 2 * h / 3))
        p.addLine(to: CGPoint(x: w, y: 2 * h / 3))
        return p
    }
}

// MARK: - UIImage normalization

private extension UIImage {
    /// Redraws the image with `.up` orientation so subsequent CGImage
    /// cropping uses the visible coordinate space (not the rotated raw
    /// pixel space). Without this step, a portrait photo from the camera
    /// — which `imageOrientation == .right` — crops sideways.
    ///
    /// The redraw is wrapped in an `autoreleasepool` so the intermediate
    /// `UIGraphicsImageRenderer` buffers are released synchronously
    /// rather than at the next runloop tick — without this, a 48 MP
    /// iPhone Pro photo (8064×6048) holds two ~187 MB bitmaps live at
    /// once and the OS jetsams the app for memory pressure on smaller
    /// devices.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else {
            cropLog.debug("normalizedUp: already .up — \(Int(self.size.width))×\(Int(self.size.height)), skipping redraw")
            return self
        }
        let mp = (size.width * size.height) / 1_000_000
        cropLog.info("normalizedUp redraw: \(Int(self.size.width))×\(Int(self.size.height)) (\(String(format: "%.1f", mp)) MP) orientation=\(self.imageOrientation.rawValue)")
        return autoreleasepool {
            let renderer = UIGraphicsImageRenderer(size: size)
            let result = renderer.image { _ in
                draw(in: CGRect(origin: .zero, size: size))
            }
            cropLog.debug("normalizedUp: redraw complete")
            return result
        }
    }
}

// MARK: - Previews

private struct PhotoCropPreviewHarness: View {
    @State private var state: PhotoCropState? = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600))
        let img = renderer.image { ctx in
            UIColor.systemPurple.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
            UIColor.white.setStroke()
            ctx.cgContext.setLineWidth(8)
            ctx.cgContext.strokeEllipse(in: CGRect(x: 100, y: 100, width: 600, height: 400))
        }
        guard let data = img.pngData() else { return nil }
        return PhotoCropState(data: data)
    }()

    var body: some View {
        if let state {
            VStack {
                PhotoCropView(state: state)
                Spacer()
            }
            .padding()
            .background(Color.DS.bg1)
        } else {
            Text("Preview image init failed")
        }
    }
}

#Preview("Light") {
    PhotoCropPreviewHarness()
}

#Preview("Dark") {
    PhotoCropPreviewHarness()
        .preferredColorScheme(.dark)
}
