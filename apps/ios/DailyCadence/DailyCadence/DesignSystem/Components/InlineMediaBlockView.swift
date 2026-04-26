import SwiftUI

/// Renders an inline media block (`TextBlock.media`) inside a card or
/// editor (Phase E.5.18). Used by both `KeepCard` and `NoteCard` so the
/// visual treatment stays identical across Board and Timeline contexts.
///
/// **Sizing.** Uses a `GeometryReader` to measure the available content
/// width, then applies `size.widthFraction` to determine the rendered
/// width. Height is derived from the asset's clamped aspect ratio
/// (`MediaPayload.aspectRatio`). The block is centered for Small /
/// Medium and full-width for Large per `size.horizontalAlignment`.
///
/// **Interaction.** The whole image is a tap target — tapping opens the
/// asset in `MediaViewerScreen` (full-screen viewer with pinch-zoom for
/// images, AVPlayer for videos). Videos display a `play.fill` glyph in
/// a `.ultraThinMaterial` circle as the press affordance.
struct InlineMediaBlockView: View {
    let payload: MediaPayload
    let size: MediaBlockSize
    /// Corner radius applied to the rendered media. `KeepCard` uses 8pt
    /// (matches the card's inner content rhythm); `NoteCard` uses 10pt
    /// for slightly softer Timeline feel.
    var cornerRadius: CGFloat = 8
    /// When true (default), tapping the media opens
    /// `MediaViewerScreen` full-screen — the read-only card behavior.
    /// Set to `false` in editor contexts so a parent `Menu` wrapper can
    /// take the tap (resize / remove).
    var isInteractive: Bool = true

    @State private var isViewerPresented = false

    var body: some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width
            let renderWidth = contentWidth * size.widthFraction
            let renderHeight = renderWidth / payload.aspectRatio

            HStack {
                if size.horizontalAlignment == .center {
                    Spacer(minLength: 0)
                }
                ZStack {
                    Color.DS.bg2
                    if let posterImage = posterImage() {
                        Image(uiImage: posterImage)
                            .resizable()
                            .scaledToFill()
                    }
                    if payload.kind == .video {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 36, height: 36)
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.DS.ink)
                                .offset(x: 1)
                        }
                    }
                }
                .frame(width: renderWidth, height: renderHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.DS.border1, lineWidth: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .onTapGesture {
                    if isInteractive { isViewerPresented = true }
                }
                if size.horizontalAlignment == .center {
                    Spacer(minLength: 0)
                }
            }
            .frame(width: contentWidth, height: renderHeight)
        }
        // The GeometryReader takes only the height of its content via
        // a fixed-size child below. We compute height from the size
        // preset + aspect ratio in the layer above; here we simply need
        // the GeometryReader to allocate the right outer height.
        .aspectRatio(aspectRatioForLayout, contentMode: .fit)
        .fullScreenCover(isPresented: $isViewerPresented) {
            MediaViewerScreen(media: payload)
        }
        .accessibilityLabel(payload.kind == .video ? "Play video" : "Open photo")
        .accessibilityAddTraits(.isButton)
    }

    /// The aspect ratio the outer container needs so the GeometryReader
    /// allocates the right vertical space. For Small / Medium the height
    /// is determined by the *rendered* width (a fraction of the content),
    /// not the full content width — so we scale the aspect ratio
    /// accordingly.
    private var aspectRatioForLayout: CGFloat {
        // height = (contentWidth * widthFraction) / payloadAspect
        // outer container has `contentWidth` width and that height,
        // so its aspect ratio = contentWidth / height
        //                     = contentWidth / (contentWidth * widthFraction / payloadAspect)
        //                     = payloadAspect / widthFraction
        payload.aspectRatio / size.widthFraction
    }

    private func posterImage() -> UIImage? {
        if let posterData = payload.posterData, let img = UIImage(data: posterData) {
            return img
        }
        return UIImage(data: payload.data)
    }
}
