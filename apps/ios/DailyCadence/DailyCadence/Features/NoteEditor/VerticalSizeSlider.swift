import SwiftUI

/// A vertical drag-to-resize control inspired by Instagram Story's text
/// size slider. Knob slides up the track to enlarge, down to shrink.
///
/// We build this from scratch instead of rotating SwiftUI's `Slider` — a
/// rotated `Slider` keeps its pre-rotation layout footprint, which fights
/// the editor's right-edge alignment and makes the hit target asymmetric.
/// A custom `DragGesture` over a track + knob ZStack is straightforward
/// and gives us a clean compact footprint (24pt wide).
///
/// **Visual**: thin pill track tinted with the design system's `bg-2` over
/// a translucent backdrop, ink-colored knob, small `Aa` glyphs at top and
/// bottom of the track to telegraph "this scales text size."
///
/// **Range**: 12...48 by default — enough room for tiny captions to
/// poster-style pull-quotes without going overboard. The caller binds a
/// `CGFloat` to `value`; updates are continuous (every drag frame).
///
/// **Hit target**: full ZStack (~48pt × full height) is hittable, so the
/// user doesn't have to land precisely on the knob — anywhere on the track
/// jumps the knob to that position.
struct VerticalSizeSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let height: CGFloat

    init(
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat> = 12...48,
        height: CGFloat = 140
    ) {
        self._value = value
        self.range = range
        self.height = height
    }

    private var normalized: CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Translucent backdrop pill — gives the knob something to read
            // against when overlaid on a tinted preview background.
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 26, height: height + 30)

            VStack(spacing: 4) {
                Text("Aa")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.DS.fg2)

                ZStack(alignment: .top) {
                    // Track
                    Capsule(style: .continuous)
                        .fill(Color.DS.fg2.opacity(0.25))
                        .frame(width: 2.5, height: height)

                    // Filled portion above the knob (visual cue: bigger = more fill)
                    Capsule(style: .continuous)
                        .fill(Color.DS.ink.opacity(0.55))
                        .frame(width: 2.5, height: max(0, (1 - normalized) * height))
                        .frame(maxHeight: height, alignment: .top)

                    // Knob — invisible 24pt wide hit-region wraps a smaller
                    // visible 14pt circle so a fat finger reliably grabs it.
                    Circle()
                        .fill(Color.DS.ink)
                        .frame(width: 14, height: 14)
                        .overlay {
                            Circle().strokeBorder(Color.DS.bg2, lineWidth: 1)
                        }
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                        .offset(y: (1 - normalized) * (height - 14) - 5)
                }
                .frame(width: 26, height: height)

                Text("Aa")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.DS.fg2)
            }
            .padding(.vertical, 6)
        }
        .frame(width: 30, height: height + 30)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let trackStart: CGFloat = 6 + 11 + 4  // top padding + label + spacing
                    let y = max(0, min(height, drag.location.y - trackStart))
                    let normalizedY = 1 - (y / height)
                    let newValue = range.lowerBound +
                        normalizedY * (range.upperBound - range.lowerBound)
                    value = min(max(newValue, range.lowerBound), range.upperBound)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Text size")
        .accessibilityValue("\(Int(value)) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(value + 2, range.upperBound)
            case .decrement:
                value = max(value - 2, range.lowerBound)
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Previews

private struct VerticalSizeSliderPreviewHarness: View {
    @State private var size: CGFloat = 16

    var body: some View {
        ZStack {
            Color.DS.bg1.ignoresSafeArea()
            HStack {
                VStack(alignment: .leading) {
                    Text("Sample text")
                        .font(.system(size: size))
                        .foregroundStyle(Color.DS.ink)
                    Text("Size: \(Int(size))pt")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.DS.fg2)
                }
                Spacer()
                VerticalSizeSlider(value: $size)
                    .padding(.trailing, 4)
            }
            .padding()
        }
    }
}

#Preview("Light") {
    VerticalSizeSliderPreviewHarness()
}

#Preview("Dark") {
    VerticalSizeSliderPreviewHarness()
        .preferredColorScheme(.dark)
}
