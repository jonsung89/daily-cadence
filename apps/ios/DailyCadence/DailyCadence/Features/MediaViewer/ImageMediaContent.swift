import SwiftUI

/// Apple Photos–style fullscreen image content: pinch to zoom (1×–5×),
/// double-tap to toggle 1×↔2.5×, pan when zoomed, **drag down at 1× to
/// dismiss**. Thumbnail is decoded synchronously in `init` so the very
/// first zoom frame already has content; the full-resolution decode
/// runs in `.task` and swaps in when ready (Apple Photos uses the same
/// trick to avoid a black canvas during the zoom-in).
///
/// **Drag-dismiss state is owned by `MediaViewerScreen`** — this view
/// writes into its bindings. The viewer applies the visible translate +
/// scale at the outer level so the image and video content share one
/// dismiss visual.
///
/// At scale > 1 the drag pans within the image; at scale 1 a downward,
/// vertically-dominant drag enters dismiss mode. Past threshold
/// (translation > 120pt or predicted velocity > 600pt) `onDismissCommitted`
/// fires; otherwise the drag springs back.
struct ImageMediaContent: View {
    let data: Data
    let thumbnailData: Data?
    @Binding var dismissOffset: CGSize
    @Binding var dismissProgress: CGFloat
    @Binding var dismissScale: CGFloat
    let onDismissCommitted: () -> Void

    @State private var uiImage: UIImage?

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    init(
        data: Data,
        thumbnailData: Data? = nil,
        dismissOffset: Binding<CGSize>,
        dismissProgress: Binding<CGFloat>,
        dismissScale: Binding<CGFloat>,
        onDismissCommitted: @escaping () -> Void
    ) {
        self.data = data
        self.thumbnailData = thumbnailData
        self._dismissOffset = dismissOffset
        self._dismissProgress = dismissProgress
        self._dismissScale = dismissScale
        self.onDismissCommitted = onDismissCommitted
        // Sync-decode the thumbnail in init — ~80 KB HEIC decodes in
        // <10 ms on modern devices and gives the first frame real
        // content during the zoom-in transition.
        if let thumbnailData, let img = UIImage(data: thumbnailData) {
            self._uiImage = State(initialValue: img)
        } else {
            self._uiImage = State(initialValue: nil)
        }
    }

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    private let doubleTapScale: CGFloat = 2.5

    private let dismissTranslationThreshold: CGFloat = 120
    private let dismissVelocityThreshold: CGFloat = 600
    private let dismissProgressDenominator: CGFloat = 200

    var body: some View {
        GeometryReader { geo in
            Group {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnificationGesture)
                        // `.highPriorityGesture` so a vertical drag wins
                        // over any system interactive-dismiss gesture.
                        .highPriorityGesture(panOrDismissGesture)
                        .onTapGesture(count: 2) { handleDoubleTap() }
                } else {
                    Color.clear
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .task {
            // Full-resolution decode off-main, swaps over the thumbnail
            // when ready. Guarded against decode failure.
            let bytes = data
            let decoded = await Task.detached { UIImage(data: bytes) }.value
            if let decoded {
                await MainActor.run { self.uiImage = decoded }
            }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = clampedScale(lastScale * value.magnification)
            }
            .onEnded { _ in
                if scale < minScale {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = minScale
                        offset = .zero
                        lastOffset = .zero
                    }
                }
                lastScale = scale
            }
    }

    /// Single drag gesture, two modes selected by current zoom level:
    /// - **scale > 1**: pan within the image (writes to local `offset`).
    /// - **scale == 1**: downward drag enters dismiss mode (writes to
    ///   the lifted `dismiss*` bindings).
    private var panOrDismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Phase F.1.2.zoomfix — explicitly disable animations
                // on the gesture's binding writes. Without this, an
                // ambient SwiftUI transaction (from a parent's
                // `.animation` modifier or a still-resolving
                // `withAnimation` from the open zoom) could attach to
                // the writes and interpolate offset/scale toward each
                // new gesture target — manifesting as duplicate-image
                // shake during the drag.
                var noAnimation = Transaction()
                noAnimation.disablesAnimations = true
                withTransaction(noAnimation) {
                    if scale > 1 {
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    } else if value.translation.height > 0 {
                        let progress = min(value.translation.height / dismissProgressDenominator, 1.0)
                        dismissOffset = value.translation
                        dismissProgress = progress
                        dismissScale = 1.0 - progress * 0.3
                    }
                }
            }
            .onEnded { value in
                if scale > 1 {
                    lastOffset = offset
                } else if dismissProgress > 0 {
                    let dy = value.translation.height
                    let predicted = value.predictedEndTranslation.height
                    if dy > dismissTranslationThreshold || predicted > dismissVelocityThreshold {
                        // Apple Photos pattern: animate offset and scale
                        // back to neutral alongside the parent's matched-geo
                        // close. Backdrop opacity stays at the dragged
                        // value (`dismissProgress` not reset) so the
                        // timeline keeps showing through the close.
                        withAnimation(.smooth(duration: 0.5)) {
                            dismissOffset = .zero
                            dismissScale = 1.0
                        }
                        onDismissCommitted()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            dismissOffset = .zero
                            dismissProgress = 0
                            dismissScale = 1.0
                        }
                    }
                }
            }
    }

    private func handleDoubleTap() {
        withAnimation(.easeOut(duration: 0.22)) {
            if scale > minScale {
                scale = minScale
                lastScale = minScale
                offset = .zero
                lastOffset = .zero
            } else {
                scale = doubleTapScale
                lastScale = doubleTapScale
            }
        }
    }

    private func clampedScale(_ raw: CGFloat) -> CGFloat {
        min(max(raw, minScale * 0.85), maxScale)
    }
}
