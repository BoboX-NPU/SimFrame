@preconcurrency import AVKit
import SwiftUI

struct DropPreviewView: View {
    @Bindable var state: AppState
    @State private var isDropTargeted = false

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
        if let image = state.previewImage {
            CheckerboardView()
                .overlay {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(.quaternary) }
        } else {
            ProgressView("Rendering preview…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var videoPreview: some View {
        if let frame = state.selectedFrame,
           let frameImage = state.selectedFrameImage,
           let player = state.videoPlayer {
            GeometryReader { proxy in
                let geometry = CompositionGeometry(frame: frame, preset: state.settings.canvasPreset)
                let scale = min(
                    proxy.size.width / max(geometry.outputSize.width, 1),
                    proxy.size.height / max(geometry.outputSize.height, 1)
                )
                let canvas = CGSize(width: geometry.outputSize.width * scale, height: geometry.outputSize.height * scale)
                let origin = CGPoint(x: (proxy.size.width - canvas.width) / 2, y: (proxy.size.height - canvas.height) / 2)

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
                                RoundedRectangle(
                                    cornerRadius: min(geometry.screenRect.width, geometry.screenRect.height) * 0.18 * scale
                                )
                            }
                        }
                        .position(
                            x: origin.x + geometry.screenRect.midX * scale,
                            y: origin.y + geometry.screenRect.midY * scale
                        )

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
        view.controlsStyle = .floating
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
