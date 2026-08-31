@preconcurrency import AVKit
import SwiftUI

struct DropPreviewView: View {
    @Bindable var state: AppState
    @State private var isDropTargeted = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            if let capture = state.capture {
                switch capture.kind {
                case .image:
                    imagePreview
                case .video:
                    videoPreview
                }
            } else {
                emptyDropZone
            }

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.tint.opacity(0.12))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
                    .padding(24)
                    .allowsHitTesting(false)
            }
        }
        .padding(20)
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            state.openCapture(first)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    private var emptyDropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop a Simulator screenshot or recording")
                .font(.title3.weight(.medium))
            Text("PNG, JPEG, HEIC, MOV, or MP4")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Choose Capture…") { state.chooseCapture() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [7, 6]))
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        GeometryReader { proxy in
            Group {
                if let image = state.previewImage {
                    CheckerboardView()
                        .overlay {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .padding(18)
                        }
                } else {
                    ProgressView("Rendering preview…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(.quaternary) }
            .onAppear {
                state.updatePreviewViewport(points: insetPreviewSize(proxy.size), displayScale: displayScale)
            }
            .onChange(of: proxy.size) { _, newSize in
                state.updatePreviewViewport(points: insetPreviewSize(newSize), displayScale: displayScale)
            }
            .onChange(of: displayScale) { _, newScale in
                state.updatePreviewViewport(points: insetPreviewSize(proxy.size), displayScale: newScale)
            }
        }
    }

    private func insetPreviewSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(1, size.width - 36), height: max(1, size.height - 36))
    }

    @ViewBuilder
    private var videoPreview: some View {
        if let frame = state.selectedFrame,
           let player = state.videoPlayer {
            GeometryReader { proxy in
                let geometry = CompositionGeometry(frame: frame, preset: state.settings.canvasPreset)
                let scale = min(
                    proxy.size.width / max(geometry.outputSize.width, 1),
                    proxy.size.height / max(geometry.outputSize.height, 1)
                )
                let canvas = CGSize(width: geometry.outputSize.width * scale, height: geometry.outputSize.height * scale)
                let origin = CGPoint(x: (proxy.size.width - canvas.width) / 2, y: (proxy.size.height - canvas.height) / 2)
                let playbackControlsWidth = VideoPreviewLayout.playbackControlsWidth(
                    availableWidth: proxy.size.width
                )

                ZStack(alignment: .topLeading) {
                    backgroundView
                        .frame(width: canvas.width, height: canvas.height)
                        .position(x: origin.x + canvas.width / 2, y: origin.y + canvas.height / 2)

                    StableVideoPlayer(player: player)
                        .frame(width: geometry.screenRect.width * scale, height: geometry.screenRect.height * scale)
                        .mask {
                            if let mask = state.selectedFrameMaskImage {
                                Image(nsImage: mask)
                                    .resizable()
                                    .interpolation(.high)
                            } else {
                                Color.clear
                            }
                        }
                        .opacity(state.selectedFrameMaskImage == nil ? 0 : 1)
                        .position(
                            x: origin.x + geometry.screenRect.midX * scale,
                            y: origin.y + geometry.screenRect.midY * scale
                        )

                    if let frameImage = state.selectedFrameImage,
                       state.selectedFrameMaskImage != nil {
                        NonInteractiveFrameArtwork(image: frameImage)
                            .frame(width: geometry.frameRect.width * scale, height: geometry.frameRect.height * scale)
                            .shadow(
                                color: .black.opacity(geometry.shadowRadius > 0 ? 0.28 : 0),
                                radius: geometry.shadowRadius * scale,
                                y: geometry.shadowOffset * scale
                            )
                            .position(
                                x: origin.x + geometry.frameRect.midX * scale,
                                y: origin.y + geometry.frameRect.midY * scale
                            )
                    } else {
                        ProgressView("Preparing video preview…")
                            .frame(width: canvas.width, height: canvas.height)
                            .position(x: origin.x + canvas.width / 2, y: origin.y + canvas.height / 2)
                    }

                    VideoPlaybackControls(controller: state.videoPlaybackController)
                        .frame(width: playbackControlsWidth)
                        .position(
                            x: proxy.size.width / 2,
                            y: VideoPreviewLayout.playbackControlsCenterY(availableHeight: proxy.size.height)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.quaternary)
                    .allowsHitTesting(false)
            }
        } else {
            ProgressView("Preparing video preview…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if state.settings.background.mode == .transparent {
            CheckerboardView()
        } else {
            Color(nsColor: state.settings.background.color.nsColor)
        }
    }
}

/// Device-frame artwork is visual chrome above the native player. A transparent
/// PNG still owns its full rectangular hit-test region unless explicitly disabled.
struct NonInteractiveFrameArtwork: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// `AVKit.VideoPlayer` currently aborts while constructing its private
/// `_AVKit_SwiftUI` bridge on macOS 27 beta. Keep SwiftUI as the owner of the
/// player and bridge only the native AppKit playback view.
struct StableVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        view.videoGravity = .resizeAspectFill
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Void) {
        view.player?.pause()
        view.player = nil
    }
}

enum VideoPreviewLayout {
    static let playbackControlsHorizontalInset: CGFloat = 24
    static let playbackControlsBottomInset: CGFloat = 16
    static let playbackControlsHeight: CGFloat = 44
    static let playbackControlsMinimumWidth: CGFloat = 400
    static let playbackControlsMaximumWidth: CGFloat = 1_000
    static let playbackControlButtonSize: CGFloat = 30
    static let playbackControlIconSize: CGFloat = 17

    static func playbackControlsWidth(availableWidth: CGFloat) -> CGFloat {
        let proposedWidth = availableWidth - playbackControlsHorizontalInset * 2
        return min(
            max(proposedWidth, playbackControlsMinimumWidth),
            playbackControlsMaximumWidth
        )
    }

    static func playbackControlsCenterY(availableHeight: CGFloat) -> CGFloat {
        max(
            playbackControlsHeight / 2,
            availableHeight - playbackControlsBottomInset - playbackControlsHeight / 2
        )
    }
}

struct VideoPlaybackControls: View {
    @Bindable var controller: VideoPlaybackController

    var body: some View {
        HStack(spacing: 10) {
            Button(action: controller.togglePlayback) {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: VideoPreviewLayout.playbackControlIconSize, weight: .semibold))
                    .frame(
                        width: VideoPreviewLayout.playbackControlButtonSize,
                        height: VideoPreviewLayout.playbackControlButtonSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(controller.isPlaying ? "Pause (Space)" : "Play (Space)")

            Text(formattedTime(controller.currentTime))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { min(controller.currentTime, max(controller.duration, 0)) },
                    set: { controller.updateSeekingTime($0) }
                ),
                in: 0...max(controller.duration, 1),
                onEditingChanged: controller.handleSeeking
            )
            .disabled(controller.duration <= 0)

            Text(formattedTime(controller.duration))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button(action: controller.toggleMute) {
                Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: VideoPreviewLayout.playbackControlIconSize, weight: .semibold))
                    .frame(
                        width: VideoPreviewLayout.playbackControlButtonSize,
                        height: VideoPreviewLayout.playbackControlButtonSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(controller.isMuted ? "Unmute" : "Mute")
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .frame(height: VideoPreviewLayout.playbackControlsHeight)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.12))
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
        .accessibilityIdentifier("video-playback-controls")
        .background {
            SpaceKeyPlaybackShortcut(action: controller.togglePlayback)
                .frame(width: 0, height: 0)
        }
        .task(id: ObjectIdentifier(controller)) {
            while !Task.isCancelled {
                controller.refreshPlaybackState()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct SpaceKeyPlaybackShortcut: NSViewRepresentable {
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.startMonitoring(hostView: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    static func shouldHandleSpaceKey(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) -> Bool {
        let conflictingModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return keyCode == 49
            && modifierFlags.intersection(conflictingModifiers).isEmpty
            && !isRepeat
    }

    @MainActor
    final class Coordinator {
        var action: @MainActor () -> Void
        private weak var hostView: NSView?
        private var eventMonitor: Any?

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        func startMonitoring(hostView: NSView) {
            self.hostView = hostView
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let window = self.hostView?.window,
                      event.window === window,
                      event.keyCode == 49 else {
                    return event
                }

                let conflictingModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
                guard event.modifierFlags.intersection(conflictingModifiers).isEmpty else {
                    return event
                }
                guard !event.isARepeat else { return nil }

                self.action()
                return nil
            }
        }

        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            hostView = nil
        }
    }
}

struct CheckerboardView: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 14
            let columns = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                    context.fill(Path(rect), with: .color(.primary.opacity(0.055)))
                }
            }
        }
        .background(.background)
    }
}
