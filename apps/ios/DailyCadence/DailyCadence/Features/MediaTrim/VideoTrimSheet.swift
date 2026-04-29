import SwiftUI
import AVFoundation
import OSLog

private let trimLog = Logger(subsystem: "com.jonsung.DailyCadence", category: "VideoTrimSheet")

/// Phase F.1.1b' — picks a `[start, end]` window out of a video that
/// exceeds `MediaImporter.videoMaxDurationSeconds`.
///
/// **Surface contract.** Caller passes a `VideoTrimSource` (carrying the
/// temp file URL the importer wrote) and two callbacks. On confirm the
/// sheet hands back a `CMTimeRange`; the caller is responsible for
/// invoking `MediaImporter.makeTrimmedVideoPayload` (which performs the
/// HEVC export with `session.timeRange = range`) and for cleaning up the
/// source URL via `MediaImporter.discardTrimSource(_:)` on cancel.
///
/// **UX.** Apple Photos pattern adapted to DailyCadence colors:
/// - Filmstrip spans the source's full duration; the trim window is
///   sage-bordered. Initial window = `[0, min(source.duration, maxTrim)]`.
/// - Left/right handles resize the window. Middle drags the whole window
///   as a unit (essential when the desired slice is in the middle of a
///   long clip). 1-second minimum, 60-second maximum.
/// - Tap the preview to play the trimmed range; playback loops back to
///   `start` when it crosses `end`.
/// - Scrubbing seeks the player so the user sees the start/end frames
///   as they drag.
struct VideoTrimSheet: View {
    let source: MediaImporter.VideoTrimSource
    let maxDurationSeconds: Double
    let onCancel: () -> Void
    let onConfirm: (CMTimeRange) -> Void

    @State private var startSeconds: Double = 0
    @State private var endSeconds: Double = 0
    @State private var playheadSeconds: Double = 0

    /// Drag-begin snapshots. SwiftUI's `DragGesture.value.translation` is
    /// **cumulative** since the gesture began, not delta-since-last-tick.
    /// Each `.onChanged` tick must compute `start = initial + translation`,
    /// not `start = current + translation` — otherwise the handle
    /// accelerates at 2× finger speed and runs away. Reset to `nil` in
    /// `.onEnded`.
    @State private var dragInitialStart: Double?
    @State private var dragInitialEnd: Double?

    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false
    @State private var boundaryObserverToken: Any?
    @State private var periodicObserverToken: Any?

    /// Generated lazily on appear — one row of evenly-spaced thumbnails
    /// across the source duration. Cached as decoded UIImages so the bar
    /// doesn't redraw expensively on each scrub frame.
    @State private var filmstripFrames: [UIImage] = []

    /// Minimum trim duration. Clamps end-start so the user can't make a
    /// 0-length clip by colliding the handles.
    private let minTrimSeconds: Double = 1.0

    /// Number of thumbnails generated for the filmstrip. 14 is dense
    /// enough at iPhone widths to give a sense of the source's content
    /// without burning seconds on `AVAssetImageGenerator`.
    private let filmstripFrameCount: Int = 14

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                preview
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                durationLabel
                    .padding(.horizontal, 20)

                trimBar
                    .padding(.horizontal, 16)

                Spacer(minLength: 0)
            }
            .background(Color.DS.bg1)
            .navigationTitle("Trim Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await setupPlayer() }
        .task { await loadFilmstrip() }
        .onDisappear { teardownPlayer() }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            Color.black
            if let player {
                TrimPlayerLayerView(player: player)
            }

            Button {
                togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: isPlaying ? 0 : 2)
                }
            }
            .opacity(isPlaying ? 0 : 1)
            .accessibilityLabel(isPlaying ? "Pause" : "Play trimmed selection")
        }
        .aspectRatio(source.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { togglePlayback() }
    }

    // MARK: - Duration label

    private var durationLabel: some View {
        HStack {
            Text(Self.formattedTime(endSeconds - startSeconds))
                .font(.DS.sans(size: 15, weight: .semibold))
                .foregroundStyle(Color.DS.ink)
            Text("of \(Self.formattedTime(maxDurationSeconds)) max")
                .font(.DS.sans(size: 13, weight: .regular))
                .foregroundStyle(Color.DS.fg2)
            Spacer()
            Text("\(Self.formattedTime(startSeconds)) – \(Self.formattedTime(endSeconds))")
                .font(.DS.sans(size: 13, weight: .regular))
                .foregroundStyle(Color.DS.fg2)
                .monospacedDigit()
        }
    }

    // MARK: - Trim bar (filmstrip + handles)

    private var trimBar: some View {
        // Filmstrip + handles laid out together so a single GeometryReader
        // owns the points-per-second mapping. 56pt-tall strip matches
        // Apple Photos' density at iPhone widths.
        GeometryReader { geo in
            let barWidth = geo.size.width
            let pointsPerSecond = barWidth / max(source.duration, 0.001)
            let startX = startSeconds * pointsPerSecond
            let endX = endSeconds * pointsPerSecond
            let windowWidth = max(endX - startX, 1)

            ZStack(alignment: .topLeading) {
                filmstrip
                    .frame(width: barWidth, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Dim everything outside the trim window.
                HStack(spacing: 0) {
                    Color.black.opacity(0.55)
                        .frame(width: max(startX, 0))
                    Color.clear
                        .frame(width: windowWidth)
                    Color.black.opacity(0.55)
                        .frame(width: max(barWidth - endX, 0))
                }
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .allowsHitTesting(false)

                // Sage border around the trim window.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.DS.sage, lineWidth: 3)
                    .frame(width: windowWidth, height: 56)
                    .offset(x: startX)
                    .allowsHitTesting(false)

                // Playhead bar (only visible while the cursor is inside
                // the trim window).
                if playheadSeconds >= startSeconds && playheadSeconds <= endSeconds {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 56)
                        .offset(x: playheadSeconds * pointsPerSecond - 1)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .allowsHitTesting(false)
                }

                // Middle drag zone — slides the window as a unit.
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: max(windowWidth - 32, 1), height: 56)
                    .offset(x: startX + 16)
                    .gesture(windowDragGesture(pointsPerSecond: pointsPerSecond))

                // Left handle.
                trimHandle(side: .left)
                    .offset(x: startX - 14)
                    .gesture(startHandleGesture(pointsPerSecond: pointsPerSecond))

                // Right handle.
                trimHandle(side: .right)
                    .offset(x: endX - 4)
                    .gesture(endHandleGesture(pointsPerSecond: pointsPerSecond))
            }
            .frame(height: 56)
        }
        .frame(height: 56)
    }

    private var filmstrip: some View {
        // Always render `filmstripFrameCount` slots so the per-slot
        // width stays stable as frames stream in. Empty slots show
        // `bg2`; loaded slots show the frame.
        HStack(spacing: 0) {
            ForEach(0..<filmstripFrameCount, id: \.self) { idx in
                if idx < filmstripFrames.count {
                    Image(uiImage: filmstripFrames[idx])
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 56)
                        .clipped()
                } else {
                    Color.DS.bg2
                        .frame(maxWidth: .infinity, maxHeight: 56)
                }
            }
        }
    }

    private enum HandleSide { case left, right }

    private func trimHandle(side: HandleSide) -> some View {
        // Sage tab the user grabs. Wider than the 3pt window border so
        // the touch target hits the 44pt minimum even though the visual
        // sits flush with the border.
        ZStack {
            RoundedRectangle(
                cornerRadius: 3,
                style: .continuous
            )
            .fill(Color.DS.sage)
            .frame(width: 18, height: 56)

            // Subtle grab affordance — a couple of vertical lines.
            HStack(spacing: 2) {
                Capsule().fill(Color.white.opacity(0.6)).frame(width: 1.5, height: 16)
                Capsule().fill(Color.white.opacity(0.6)).frame(width: 1.5, height: 16)
            }
        }
        .contentShape(Rectangle().inset(by: -10))
        .accessibilityLabel(side == .left ? "Trim start handle" : "Trim end handle")
    }

    // MARK: - Drag gestures

    private func startHandleGesture(pointsPerSecond: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard pointsPerSecond > 0 else { return }
                if dragInitialStart == nil {
                    dragInitialStart = startSeconds
                    pausePlayback()
                }
                let base = dragInitialStart ?? startSeconds
                let proposed = base + Double(value.translation.width) / pointsPerSecond
                applyStart(proposed)
            }
            .onEnded { _ in
                dragInitialStart = nil
                seekPrecise(to: startSeconds)
            }
    }

    private func endHandleGesture(pointsPerSecond: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard pointsPerSecond > 0 else { return }
                if dragInitialEnd == nil {
                    dragInitialEnd = endSeconds
                    pausePlayback()
                }
                let base = dragInitialEnd ?? endSeconds
                let proposed = base + Double(value.translation.width) / pointsPerSecond
                applyEnd(proposed)
            }
            .onEnded { _ in
                dragInitialEnd = nil
                seekPrecise(to: endSeconds)
            }
    }

    private func windowDragGesture(pointsPerSecond: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard pointsPerSecond > 0 else { return }
                if dragInitialStart == nil {
                    dragInitialStart = startSeconds
                    dragInitialEnd = endSeconds
                    pausePlayback()
                }
                let baseStart = dragInitialStart ?? startSeconds
                let baseEnd = dragInitialEnd ?? endSeconds
                let windowDuration = baseEnd - baseStart
                let delta = Double(value.translation.width) / pointsPerSecond
                var newStart = baseStart + delta
                newStart = max(0, min(newStart, source.duration - windowDuration))
                startSeconds = newStart
                endSeconds = newStart + windowDuration
                seekScrub(to: newStart)
            }
            .onEnded { _ in
                dragInitialStart = nil
                dragInitialEnd = nil
                seekPrecise(to: startSeconds)
            }
    }

    private func applyStart(_ proposed: Double) {
        var newStart = max(0, min(proposed, endSeconds - minTrimSeconds))
        // If the window would exceed the cap, pull the right handle in
        // toward the left — matches Apple Photos: dragging the left
        // handle leftward past the cap slides the whole window rather
        // than refusing the drag.
        if endSeconds - newStart > maxDurationSeconds {
            newStart = max(0, endSeconds - maxDurationSeconds)
        }
        startSeconds = newStart
        seekScrub(to: newStart)
    }

    private func applyEnd(_ proposed: Double) {
        var newEnd = min(source.duration, max(proposed, startSeconds + minTrimSeconds))
        if newEnd - startSeconds > maxDurationSeconds {
            newEnd = startSeconds + maxDurationSeconds
        }
        endSeconds = newEnd
        seekScrub(to: newEnd)
    }

    /// Scrub-mode seek (during drag). **Fire-and-forget** — no `Task`,
    /// no `await`. AVPlayer collapses overlapping seek requests
    /// internally; awaiting each one queues them up and the queue
    /// keeps draining after the finger lifts (the "doesn't stop when
    /// I stop" bug from F.1.1b' v1). `toleranceAfter: .positiveInfinity`
    /// lets the player snap to the next keyframe — fast and visually
    /// fine for scrub previews.
    private func seekScrub(to seconds: Double) {
        playheadSeconds = seconds
        guard let player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
    }

    /// Frame-accurate seek used after a scrub ends or before play.
    /// Same fire-and-forget pattern; tolerance .zero gets the exact
    /// frame for the start/end preview.
    private func seekPrecise(to seconds: Double) {
        playheadSeconds = seconds
        guard let player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Playback

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // If the playhead ran past the trim window or is at the end,
            // jump back to the trim start before playing.
            if playheadSeconds < startSeconds || playheadSeconds >= endSeconds - 0.05 {
                seekPrecise(to: startSeconds)
            }
            registerLoopBoundary(player: player)
            player.play()
            isPlaying = true
        }
    }

    private func pausePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        }
    }

    /// Re-registers the boundary observer at the current `endSeconds`.
    /// Called before each play so handle drags during pause are honored.
    private func registerLoopBoundary(player: AVPlayer) {
        if let token = boundaryObserverToken {
            player.removeTimeObserver(token)
            boundaryObserverToken = nil
        }
        let endTime = CMTime(seconds: endSeconds, preferredTimescale: 600)
        boundaryObserverToken = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: endTime)],
            queue: .main
        ) {
            Task { @MainActor in
                seekPrecise(to: startSeconds)
                player.play()
            }
        }
    }

    // MARK: - Setup / teardown

    private func setupPlayer() async {
        // Initialise the trim window: cap starts at the lower of source
        // duration and max-trim. Most picks will be > maxTrim (that's
        // what put us in this sheet), so the initial window is exactly
        // [0, maxTrim].
        let initialEnd = min(source.duration, maxDurationSeconds)
        await MainActor.run {
            startSeconds = 0
            endSeconds = initialEnd
            playheadSeconds = 0
        }

        let player = AVPlayer(url: source.sourceURL)
        // Mute by default — trim is a visual decision and preview audio
        // would surprise anyone trimming in public.
        player.isMuted = true
        await MainActor.run {
            self.player = player
        }

        // Periodic observer keeps the playhead in sync during playback.
        // 30 Hz is smooth enough for the 2pt playhead bar without
        // hammering main thread.
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            playheadSeconds = time.seconds
        }
        await MainActor.run {
            self.periodicObserverToken = token
        }
    }

    private func teardownPlayer() {
        if let player {
            if let token = boundaryObserverToken {
                player.removeTimeObserver(token)
            }
            if let token = periodicObserverToken {
                player.removeTimeObserver(token)
            }
            player.pause()
        }
        boundaryObserverToken = nil
        periodicObserverToken = nil
        player = nil
    }

    // MARK: - Filmstrip

    private func loadFilmstrip() async {
        let t0 = Date()
        let asset = AVURLAsset(url: source.sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // 120pt × 3× = ~360px is plenty for a 56pt-tall strip on retina.
        // Smaller decode = faster generation on heavy codecs.
        generator.maximumSize = CGSize(width: 120, height: 120)
        // `.positiveInfinity` tolerance = "any nearby keyframe" — fastest
        // option; the generator can skip seeking to a precise inter-frame.
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let count = filmstripFrameCount
        let times: [CMTime] = (0..<count).map { idx in
            let t = source.duration * (Double(idx) + 0.5) / Double(count)
            return CMTime(seconds: t, preferredTimescale: 600)
        }

        // Publish frames as they generate so the user sees the strip fill
        // in incrementally rather than waiting for all 14.
        var loaded = 0
        for t in times {
            do {
                let (cgImage, _) = try await generator.image(at: t)
                let img = UIImage(cgImage: cgImage)
                await MainActor.run {
                    self.filmstripFrames.append(img)
                }
                loaded += 1
            } catch {
                // Skip failed frames — bar is decorative; the trim still works.
            }
        }
        trimLog.info("filmstrip: \(loaded)/\(count) frames in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { onCancel() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
                let end = CMTime(seconds: endSeconds, preferredTimescale: 600)
                let range = CMTimeRange(start: start, end: end)
                onConfirm(range)
            }
            .fontWeight(.semibold)
            .tint(Color.DS.sageDeep)
            .disabled((endSeconds - startSeconds) < minTrimSeconds)
        }
    }

    // MARK: - Time formatting

    private static func formattedTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - AVPlayerLayer wrapper

/// Bare `AVPlayerLayer` host — `AVKit.VideoPlayer` brings its own
/// playback chrome and tap-to-show-controls behavior we don't want
/// during trim. This is the minimal "show me the frames" surface.
private struct TrimPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
