import SwiftUI
import UIKit

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

/// Photos.app-style crop UX (Phase E.4.2 rewrite).
///
/// **Model.** The image is fixed at scale-to-fit inside the canvas. A
/// **crop rectangle** floats on top, defined in canvas coordinates.
/// Corner handles resize it; the central area drags it. Areas outside
/// the crop rect are dimmed via an eo-fill `Canvas` mask. Aspect chips
/// constrain the crop's shape.
///
/// **What's deferred.** Pinch-to-zoom on the image itself is a future
/// polish — combined with the crop rectangle it requires a coordinated
/// gesture system (handle drags must take priority over pan, pinch must
/// take priority over both, and the crop rect needs to track the
/// transformed image rect). The current corner-drag + center-drag UX
/// covers the core "crop to a chosen region" flow; pinch zoom can come
/// in a follow-up if users want to crop smaller than scale-to-fit.
@Observable
final class PhotoCropState {
    let original: UIImage

    var aspect: PhotoCropAspect = .free {
        didSet {
            // When the aspect chip changes, snap the crop rect to the new
            // shape — center-fit it inside the visible image rect.
            cropRect = aspectFittedCropRect(in: imageRect)
        }
    }

    /// Where the source image is laid out inside the canvas (canvas
    /// coordinates). Set by the view via `setImageRect(_:)` once it
    /// has a size from `GeometryReader`.
    private(set) var imageRect: CGRect = .zero

    /// The crop rectangle in canvas coordinates — what the dimmed
    /// overlay punches a hole through.
    var cropRect: CGRect = .zero

    init?(data: Data) {
        guard let raw = UIImage(data: data) else { return nil }
        self.original = raw.normalizedUp()
    }

    /// Called by `PhotoCropView` after measuring the canvas. Recomputes
    /// the visible image rect at scale-to-fit and re-fits the crop rect
    /// inside it.
    func setImageRect(_ rect: CGRect) {
        let didChange = rect != imageRect
        imageRect = rect
        if cropRect == .zero || didChange {
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

        // Map crop rect (canvas coords) → source image pixel coords.
        let scaleX = imageW / imageRect.width
        let scaleY = imageH / imageRect.height
        var x = (cropRect.minX - imageRect.minX) * scaleX
        var y = (cropRect.minY - imageRect.minY) * scaleY
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

    /// Crop rect at the moment a drag began. We snapshot this so the
    /// in-flight `DragGesture.translation` always applies to a stable
    /// starting rect rather than the live `cropRect` (which would
    /// compound the same translation every frame).
    @State private var dragStartRect: CGRect = .zero

    /// Minimum crop dimension in canvas coords. Below this the crop can
    /// be hard to grab and the resulting image is too small to be useful.
    private let minCropDimension: CGFloat = 60

    /// Hit area for each corner handle. The visible square is smaller —
    /// this is just the touch target.
    private let handleHitSize: CGFloat = 36

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

                // Image scaled-to-fit at the computed rect.
                Image(uiImage: state.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                // Dim outside the crop rect using even-odd fill.
                dimOverlay(canvas: geo.size)

                // Crop rect outline + handles + center drag.
                cropFrame(imageRect: imageRect)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
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

    // MARK: - Crop frame (border + handles + center drag)

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

            // Center drag area — invisible rectangle inside the crop rect,
            // shrunk so it doesn't overlap the corner hit zones.
            let centerInset = handleHitSize / 2
            let centerW = max(0, r.width - centerInset * 2)
            let centerH = max(0, r.height - centerInset * 2)
            if centerW > 0, centerH > 0 {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: centerW, height: centerH)
                    .position(x: r.midX, y: r.midY)
                    .contentShape(Rectangle())
                    .gesture(centerDragGesture(imageRect: imageRect))
            }

            // Four corner handles.
            cornerHandle(at: .topLeft,     position: CGPoint(x: r.minX, y: r.minY), imageRect: imageRect)
            cornerHandle(at: .topRight,    position: CGPoint(x: r.maxX, y: r.minY), imageRect: imageRect)
            cornerHandle(at: .bottomLeft,  position: CGPoint(x: r.minX, y: r.maxY), imageRect: imageRect)
            cornerHandle(at: .bottomRight, position: CGPoint(x: r.maxX, y: r.maxY), imageRect: imageRect)
        }
    }

    private func cornerHandle(at corner: Corner, position: CGPoint, imageRect: CGRect) -> some View {
        ZStack {
            // Larger transparent hit area
            Color.clear.frame(width: handleHitSize, height: handleHitSize)
            // Visible glyph: an L-shape that hugs the corner
            CornerGlyph(corner: corner)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .square))
                .frame(width: 18, height: 18)
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

    private func centerDragGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragStartRect == .zero { dragStartRect = state.cropRect }
                var rect = dragStartRect
                rect.origin.x += drag.translation.width
                rect.origin.y += drag.translation.height
                state.cropRect = clampPosition(rect, in: imageRect)
            }
            .onEnded { _ in dragStartRect = .zero }
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

    private func clampPosition(_ proposed: CGRect, in container: CGRect) -> CGRect {
        var rect = proposed
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
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
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
