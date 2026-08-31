@preconcurrency import AVFoundation
import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

struct LatestRequestGeneration: Sendable {
    private(set) var value = 0

    mutating func begin() -> Int {
        value &+= 1
        return value
    }

    func accepts(_ request: Int) -> Bool {
        request == value
    }
}

@MainActor
protocol VideoPlaybackSession: AnyObject {
    var currentSeconds: Double { get }
    var durationSeconds: Double { get }
    var isPlaying: Bool { get }
    var isMuted: Bool { get set }

    func play()
    func pause()
    func seek(to seconds: Double)
}

@MainActor
private final class AVPlayerPlaybackSession: VideoPlaybackSession {
    let player: AVPlayer

    init(player: AVPlayer) {
        self.player = player
    }

    var currentSeconds: Double { player.currentTime().seconds }
    var durationSeconds: Double { player.currentItem?.duration.seconds ?? 0 }
    var isPlaying: Bool { player.timeControlStatus == .playing }
    var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }
}

@MainActor
@Observable
final class VideoPlaybackController {
    @ObservationIgnored private var session: (any VideoPlaybackSession)?

    private(set) var currentTime = 0.0
    private(set) var duration = 0.0
    private(set) var isPlaying = false
    private(set) var isSeeking = false
    private(set) var isMuted = false

    func bind(to player: AVPlayer?) {
        bind(to: player.map { AVPlayerPlaybackSession(player: $0) })
    }

    func bind(to session: (any VideoPlaybackSession)?) {
        self.session?.pause()
        self.session = session
        currentTime = 0
        duration = 0
        isPlaying = false
        isSeeking = false
        isMuted = session?.isMuted ?? false
        refreshPlaybackState()
    }

    func pauseForFrameChange() {
        guard let session else { return }
        session.pause()
        if session.currentSeconds.isFinite {
            currentTime = max(session.currentSeconds, 0)
        }
        if session.durationSeconds.isFinite {
            duration = max(session.durationSeconds, 0)
        }
        isPlaying = false
        isMuted = session.isMuted
    }

    func togglePlayback() {
        guard let session else { return }
        if isPlaying || session.isPlaying {
            session.pause()
            isPlaying = false
            return
        }

        if duration > 0, currentTime >= duration - 0.05 {
            currentTime = 0
            session.seek(to: 0)
        }
        session.play()
        isPlaying = true
    }

    func toggleMute() {
        guard let session else { return }
        session.isMuted.toggle()
        isMuted = session.isMuted
    }

    func updateSeekingTime(_ seconds: Double) {
        currentTime = max(seconds, 0)
    }

    func handleSeeking(_ editing: Bool) {
        isSeeking = editing
        guard !editing, let session else { return }
        session.seek(to: currentTime)
    }

    func refreshPlaybackState() {
        guard let session else { return }
        if !isSeeking, session.currentSeconds.isFinite {
            currentTime = max(session.currentSeconds, 0)
        }
        if session.durationSeconds.isFinite {
            duration = max(session.durationSeconds, 0)
        }
        isPlaying = session.isPlaying
        isMuted = session.isMuted
    }
}

@MainActor
@Observable
final class AppState {
    private let libraryService: any FrameLibraryServing
    private let imageRenderer: ImageRenderer
    private let videoRenderer: VideoRenderer
    private let recentStore: RecentCaptureStore
    @ObservationIgnored private var captureAccessURL: URL?
    @ObservationIgnored private var captureAccessIsActive = false
    @ObservationIgnored private var currentVideoJob: VideoRenderJob?
    private var selectedAssets: FrameRenderAssets?
    @ObservationIgnored private var frameImportTask: Task<Void, Never>?
    @ObservationIgnored private var frameLoadTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var resizeTask: Task<Void, Never>?
    @ObservationIgnored private var copyTask: Task<Void, Never>?
    @ObservationIgnored private var selectionRequests = LatestRequestGeneration()
    @ObservationIgnored private var previewRequests = LatestRequestGeneration()
    @ObservationIgnored private var frameImportRequests = LatestRequestGeneration()
    @ObservationIgnored private var previewViewportPixels = CGSize(width: 1_600, height: 1_200)

    var manifest: FrameLibraryManifest?
    var capture: CaptureDescriptor?
    var detection: DetectionResult?
    var selectedFrameID: String?
    var settings = RenderSettings()
    var previewImage: NSImage?
    var selectedFrameImage: NSImage?
    var selectedFrameMaskImage: NSImage?
    var videoPlayer: AVPlayer?
    let videoPlaybackController = VideoPlaybackController()
    var recentCaptures: [RecentCaptureRecord] = []
    var frameImportPhase: FrameImportPhase?
    var isExporting = false
    var isCopying = false
    var exportProgress = 0.0
    var statusMessage = "Import an Apple device frame library to begin."
    var errorMessage: String?
    var importWarnings: [String] = []

    init(
        libraryService: any FrameLibraryServing = FrameLibraryService(),
        imageRenderer: ImageRenderer = ImageRenderer(),
        videoRenderer: VideoRenderer = VideoRenderer()
    ) {
        self.libraryService = libraryService
        self.imageRenderer = imageRenderer
        self.videoRenderer = videoRenderer
        recentStore = RecentCaptureStore()
        recentCaptures = recentStore.load()
        Task { await bootstrap() }
    }

    var frames: [DeviceFrame] { manifest?.frames ?? [] }
    var selectedFrame: DeviceFrame? { frames.first { $0.id == selectedFrameID } }
    var deviceNames: [String] {
        Array(Set(frames.map(\.device))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var selectedDevice: String? { selectedFrame?.device }
    var availableVariants: [String] {
        guard let frame = selectedFrame else { return [] }
        return Array(Set(frames.filter {
            $0.device == frame.device && $0.orientation == frame.orientation
        }.map(\.variant))).sorted()
    }
    var canExport: Bool {
        guard capture != nil, selectedFrame != nil, !isExporting else { return false }
        return !(settings.exportFormat == .mp4 && settings.background.mode == .transparent)
    }
    var canCopyImage: Bool {
        capture?.kind == .image && selectedFrame != nil && selectedAssets != nil && !isCopying
    }
    var isImportingFrames: Bool { frameImportPhase != nil }
    var canCancelFrameImport: Bool { frameImportPhase?.isCancellable == true }
    var cropWarning: Bool {
        guard let capture, let selectedFrame else { return false }
        return DeviceDetector.needsCropping(captureSize: capture.pixelSize, frame: selectedFrame)
    }

    func chooseFrameLibrary() {
        guard !isImportingFrames else { return }
        let panel = NSOpenPanel()
        panel.title = manifest == nil ? "Import Apple Device Frames" : "Replace Device Frame Library"
        panel.prompt = "Import"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFrameLibrary(from: url)
    }

    func importFrameLibrary(from url: URL) {
        guard frameImportTask == nil, frameImportPhase == nil else { return }
        videoPlaybackController.pauseForFrameChange()
        let request = frameImportRequests.begin()
        frameImportPhase = .scanning
        errorMessage = nil
        statusMessage = FrameImportPhase.scanning.detailText
        let service = libraryService
        frameImportTask = Task { [weak self] in
            do {
                let report = try await service.importLibrary(from: url) { [weak self] phase in
                    guard let self else { return }
                    await self.updateFrameImportPhase(phase, request: request)
                }
                guard let self, frameImportRequests.accepts(request) else { return }
                manifest = report.manifest
                importWarnings = report.skippedFiles
                selectedFrameID = report.manifest.frames.first?.id
                settings.frameID = selectedFrameID
                frameImportPhase = .loadingSelection
                statusMessage = FrameImportPhase.loadingSelection.detailText
                beginSelectedFrameLoad(
                    completingImport: request,
                    importedFrameCount: report.manifest.frames.count
                )
            } catch is CancellationError {
                guard let self, frameImportRequests.accepts(request) else { return }
                frameImportTask = nil
                frameImportPhase = nil
                statusMessage = "Import cancelled. Existing device frames were kept."
            } catch {
                guard let self, frameImportRequests.accepts(request) else { return }
                frameImportTask = nil
                frameImportPhase = nil
                present(error)
            }
        }
    }

    func cancelFrameImport() {
        guard canCancelFrameImport, let frameImportTask else { return }
        frameImportPhase = .cancelling
        statusMessage = FrameImportPhase.cancelling.detailText
        frameImportTask.cancel()
    }

    func chooseCapture() {
        let panel = NSOpenPanel()
        panel.title = "Open Simulator Capture"
        panel.prompt = "Open"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .movie, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openCapture(url)
    }

    func openCapture(_ url: URL) {
        errorMessage = nil
        statusMessage = "Inspecting \(url.lastPathComponent)…"
        let accessIsActive = url.startAccessingSecurityScopedResource()
        Task {
            do {
                let descriptor = try await CaptureService.inspect(url: url)
                if captureAccessIsActive { captureAccessURL?.stopAccessingSecurityScopedResource() }
                captureAccessURL = url
                captureAccessIsActive = accessIsActive
                capture = descriptor
                recentCaptures = recentStore.add(url: url, kind: descriptor.kind, to: recentCaptures)
                settings.exportFormat = descriptor.kind == .image ? .png : .mov
                videoPlayer = descriptor.kind == .video ? AVPlayer(url: url) : nil
                videoPlaybackController.bind(to: videoPlayer)
                detectAndPreview()
            } catch {
                if accessIsActive { url.stopAccessingSecurityScopedResource() }
                present(error)
            }
        }
    }

    func openRecent(_ record: RecentCaptureRecord) {
        guard let url = recentStore.resolve(record) else {
            recentCaptures.removeAll { $0.id == record.id }
            errorMessage = "That recent file is no longer available."
            return
        }
        openCapture(url)
    }

    func selectFrame(id: String) {
        guard id != selectedFrameID, frames.contains(where: { $0.id == id }) else { return }
        selectedFrameID = id
        settings.frameID = id
        UserDefaults.standard.set(id, forKey: "lastFrameID")
        beginSelectedFrameLoad()
    }

    func selectDevice(_ device: String) {
        guard let current = selectedFrame else { return }
        let best = frames.first {
            $0.device == device && $0.orientation == current.orientation && $0.variant == current.variant
        } ?? frames.first { $0.device == device && $0.orientation == current.orientation }
            ?? frames.first { $0.device == device }
        if let best { selectFrame(id: best.id) }
    }

    func selectOrientation(_ orientation: FrameOrientation) {
        guard let current = selectedFrame else { return }
        let best = frames.first {
            $0.device == current.device && $0.orientation == orientation && $0.variant == current.variant
        } ?? frames.first { $0.device == current.device && $0.orientation == orientation }
        if let best { selectFrame(id: best.id) }
    }

    func selectVariant(_ variant: String) {
        guard let current = selectedFrame,
              let best = frames.first(where: {
                  $0.device == current.device && $0.orientation == current.orientation && $0.variant == variant
              }) else { return }
        selectFrame(id: best.id)
    }

    func setCanvasPreset(_ preset: CanvasPreset) {
        settings.canvasPreset = preset
        refreshPreview()
    }

    func setBackgroundMode(_ mode: BackgroundMode) {
        settings.background.mode = mode
        refreshPreview()
    }

    func setBackgroundColor(_ color: NSColor) {
        settings.background = RenderBackground(mode: .solid, color: RGBAColor(nsColor: color))
        refreshPreview()
    }

    func setExportFormat(_ format: ExportFormat) {
        settings.exportFormat = format
    }

    func updatePreviewViewport(points: CGSize, displayScale: CGFloat) {
        guard points.width > 0, points.height > 0, displayScale > 0 else { return }
        let pixels = CGSize(
            width: max(1, (points.width * displayScale).rounded()),
            height: max(1, (points.height * displayScale).rounded())
        )
        guard pixels != previewViewportPixels else { return }
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self else { return }
            previewViewportPixels = pixels
            refreshPreview()
        }
    }

    func refreshPreview() {
        previewTask?.cancel()
        let request = previewRequests.begin()
        guard let capture, capture.kind == .image,
              let frame = selectedFrame,
              let assets = selectedAssets else {
            if capture?.kind != .video { previewImage = nil }
            return
        }
        previewImage = nil
        let renderer = imageRenderer
        let currentSettings = settings
        let maximumPixelSize = previewViewportPixels
        previewTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(20))
                let image = try await Task.detached(priority: .userInitiated) {
                    try renderer.preview(
                        contentURL: capture.url,
                        assets: assets,
                        frame: frame,
                        settings: currentSettings,
                        maximumPixelSize: maximumPixelSize
                    )
                }.value
                try Task.checkCancellation()
                guard let self, previewRequests.accepts(request),
                      selectedFrameID == frame.id,
                      settings == currentSettings else { return }
                previewImage = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
                statusMessage = cropWarning ? "Preview ready · capture will be center-cropped." : "Preview ready."
            } catch is CancellationError {
                return
            } catch {
                guard let self, previewRequests.accepts(request) else { return }
                present(error)
            }
        }
    }

    func export() {
        guard let capture, let frame = selectedFrame else {
            present(SimFrameError.noSelection)
            return
        }
        if settings.exportFormat == .mp4 && settings.background.mode == .transparent {
            present(SimFrameError.mp4RequiresOpaqueBackground)
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Framed Capture"
        panel.nameFieldStringValue = "\(capture.displayName)-framed.\(settings.exportFormat.fileExtension)"
        panel.allowedContentTypes = settings.exportFormat == .png ? [.png] :
            (settings.exportFormat == .mov ? [.quickTimeMovie] : [.mpeg4Movie])
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let destinationAccessIsActive = destination.startAccessingSecurityScopedResource()

        isExporting = true
        exportProgress = 0
        errorMessage = nil
        statusMessage = "Exporting…"
        let currentSettings = settings
        Task {
            defer {
                if destinationAccessIsActive { destination.stopAccessingSecurityScopedResource() }
            }
            do {
                let assets = try await libraryService.assets(for: frame)
                if capture.kind == .image {
                    let renderer = imageRenderer
                    try await Task.detached(priority: .userInitiated) {
                        let image = try renderer.render(
                            contentURL: capture.url,
                            assets: assets,
                            frame: frame,
                            settings: currentSettings
                        )
                        try renderer.writePNG(image, to: destination)
                    }.value
                    exportProgress = 1
                } else {
                    let job = VideoRenderJob()
                    currentVideoJob = job
                    try await videoRenderer.render(
                        sourceURL: capture.url,
                        destinationURL: destination,
                        assets: assets,
                        frame: frame,
                        settings: currentSettings,
                        job: job,
                        progress: { [weak self] value in
                            Task { @MainActor in self?.exportProgress = value }
                        }
                    )
                }
                isExporting = false
                currentVideoJob = nil
                statusMessage = "Exported \(destination.lastPathComponent)."
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch is CancellationError {
                isExporting = false
                currentVideoJob = nil
                statusMessage = "Export cancelled."
            } catch {
                isExporting = false
                currentVideoJob = nil
                present(error)
            }
        }
    }

    func cancelExport() {
        currentVideoJob?.cancel()
        statusMessage = "Cancelling export…"
    }

    func copyImage() {
        guard let capture, capture.kind == .image,
              let frame = selectedFrame,
              let assets = selectedAssets,
              !isCopying else { return }
        isCopying = true
        statusMessage = "Preparing full-resolution copy…"
        let renderer = imageRenderer
        let currentSettings = settings
        copyTask?.cancel()
        copyTask = Task { [weak self] in
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    try renderer.render(
                        contentURL: capture.url,
                        assets: assets,
                        frame: frame,
                        settings: currentSettings
                    )
                }.value
                try Task.checkCancellation()
                guard let self else { return }
                let pasteboardImage = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([pasteboardImage])
                isCopying = false
                statusMessage = "Copied full-resolution framed image to the clipboard."
            } catch is CancellationError {
                self?.isCopying = false
            } catch {
                guard let self else { return }
                isCopying = false
                present(error)
            }
        }
    }

    func openAppleResources() {
        NSWorkspace.shared.open(URL(string: "https://developer.apple.com/design/resources/")!)
    }

    func openMarketingGuidelines() {
        NSWorkspace.shared.open(URL(string: "https://developer.apple.com/app-store/marketing/guidelines/")!)
    }

    func clearError() { errorMessage = nil }

    private func bootstrap() async {
        do {
            statusMessage = "Preparing device frame masks…"
            manifest = try await libraryService.loadManifest()
            selectedFrameID = UserDefaults.standard.string(forKey: "lastFrameID")
            if selectedFrame == nil { selectedFrameID = manifest?.frames.first?.id }
            settings.frameID = selectedFrameID
            if let manifest {
                statusMessage = "\(manifest.frames.count) device frames ready. Drop a capture to begin."
                beginSelectedFrameLoad()
            }
            await handleLaunchArguments()
        } catch {
            present(error)
        }
    }

    private func handleLaunchArguments() async {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--test-library"), arguments.indices.contains(index + 1) {
            importFrameLibrary(from: URL(fileURLWithPath: arguments[index + 1]))
        }
        if let index = arguments.firstIndex(of: "--test-capture"), arguments.indices.contains(index + 1) {
            openCapture(URL(fileURLWithPath: arguments[index + 1]))
        }
    }

    private func detectAndPreview() {
        guard let capture, !frames.isEmpty else {
            statusMessage = manifest == nil ? "Import a device frame library first." : "No compatible frames are available."
            return
        }
        detection = DeviceDetector.detect(
            capture: capture,
            frames: frames,
            lastFrameID: UserDefaults.standard.string(forKey: "lastFrameID")
        )
        if let best = detection?.best { selectedFrameID = best.frame.id }
        settings.frameID = selectedFrameID
        beginSelectedFrameLoad()
        if capture.kind == .video {
            statusMessage = detection?.isAmbiguous == true ? "Video ready · choose the correct device." : "Video ready."
        } else if detection?.isAmbiguous == true {
            statusMessage = "Multiple devices share this resolution · choose the correct device."
        }
    }

    private func beginSelectedFrameLoad(
        completingImport importRequest: Int? = nil,
        importedFrameCount: Int? = nil
    ) {
        if capture?.kind == .video {
            videoPlaybackController.pauseForFrameChange()
        }
        frameLoadTask?.cancel()
        previewTask?.cancel()
        copyTask?.cancel()
        isCopying = false
        let request = selectionRequests.begin()
        selectedAssets = nil
        selectedFrameImage = nil
        selectedFrameMaskImage = nil
        if capture?.kind == .image { previewImage = nil }
        guard let frame = selectedFrame else {
            if let importRequest, let importedFrameCount {
                finishFrameImport(request: importRequest, importedFrameCount: importedFrameCount)
            }
            return
        }

        frameLoadTask = Task { [weak self] in
            do {
                guard let self else { return }
                let assets = try await libraryService.assets(for: frame)
                try Task.checkCancellation()
                guard selectionRequests.accepts(request), selectedFrameID == frame.id else { return }
                selectedAssets = assets
                selectedFrameImage = NSImage(
                    cgImage: assets.artwork,
                    size: NSSize(width: assets.artwork.width, height: assets.artwork.height)
                )
                selectedFrameMaskImage = NSImage(
                    cgImage: assets.screenMask,
                    size: NSSize(width: assets.screenMask.width, height: assets.screenMask.height)
                )
                refreshPreview()
                if let importRequest, let importedFrameCount {
                    finishFrameImport(request: importRequest, importedFrameCount: importedFrameCount)
                }
            } catch is CancellationError {
                if let self, let importRequest, let importedFrameCount {
                    finishFrameImport(request: importRequest, importedFrameCount: importedFrameCount)
                }
                return
            } catch {
                guard let self, selectionRequests.accepts(request) else { return }
                if let importRequest, frameImportRequests.accepts(importRequest) {
                    frameImportTask = nil
                    frameImportPhase = nil
                }
                present(error)
            }
        }
    }

    private func updateFrameImportPhase(_ phase: FrameImportPhase, request: Int) {
        guard frameImportRequests.accepts(request), frameImportPhase != .cancelling else { return }
        frameImportPhase = phase
        statusMessage = phase.detailText
    }

    private func finishFrameImport(request: Int, importedFrameCount: Int) {
        guard frameImportRequests.accepts(request) else { return }
        frameImportTask = nil
        frameImportPhase = nil
        statusMessage = "Imported \(importedFrameCount) device frames."
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        statusMessage = "Action failed."
        AppLog.app.error("\(error.localizedDescription, privacy: .public)")
    }
}
