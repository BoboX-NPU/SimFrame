@preconcurrency import AVFoundation
import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppState {
    private let libraryService: FrameLibraryService
    private let imageRenderer: ImageRenderer
    private let videoRenderer: VideoRenderer
    private let recentStore: RecentCaptureStore
    private var captureAccessURL: URL?
    private var captureAccessIsActive = false
    private var currentVideoJob: VideoRenderJob?

    var manifest: FrameLibraryManifest?
    var capture: CaptureDescriptor?
    var detection: DetectionResult?
    var selectedFrameID: String?
    var settings = RenderSettings()
    var previewImage: NSImage?
    var selectedFrameImage: NSImage?
    var videoPlayer: AVPlayer?
    var recentCaptures: [RecentCaptureRecord] = []
    var isImportingFrames = false
    var isExporting = false
    var exportProgress = 0.0
    var statusMessage = "Import an Apple device frame library to begin."
    var errorMessage: String?
    var importWarnings: [String] = []

    init(
        libraryService: FrameLibraryService = FrameLibraryService(),
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
    var selectedFrame: DeviceFrame? {
        frames.first { $0.id == selectedFrameID }
    }
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
    var cropWarning: Bool {
        guard let capture, let selectedFrame else { return false }
        return DeviceDetector.needsCropping(captureSize: capture.pixelSize, frame: selectedFrame)
    }

    func chooseFrameLibrary() {
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
        isImportingFrames = true
        errorMessage = nil
        statusMessage = "Scanning device frames…"
        Task {
            do {
                let report = try await libraryService.importLibrary(from: url)
                manifest = report.manifest
                importWarnings = report.skippedFiles
                selectedFrameID = report.manifest.frames.first?.id
                settings.frameID = selectedFrameID
                isImportingFrames = false
                statusMessage = "Imported \(report.manifest.frames.count) device frames."
                await loadSelectedFrameImage()
                if capture != nil { detectAndPreview() }
            } catch {
                isImportingFrames = false
                present(error)
            }
        }
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
        guard frames.contains(where: { $0.id == id }) else { return }
        selectedFrameID = id
        settings.frameID = id
        UserDefaults.standard.set(id, forKey: "lastFrameID")
        Task {
            await loadSelectedFrameImage()
            refreshPreview()
        }
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

    func refreshPreview() {
        guard let capture, capture.kind == .image, let frame = selectedFrame else {
            previewImage = nil
            return
        }
        Task {
            do {
                let frameURL = await libraryService.frameURL(for: frame)
                previewImage = try imageRenderer.preview(
                    contentURL: capture.url,
                    frameURL: frameURL,
                    frame: frame,
                    settings: settings
                )
                statusMessage = cropWarning ? "Preview ready · capture will be center-cropped." : "Preview ready."
            } catch {
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
                let frameURL = await libraryService.frameURL(for: frame)
                if capture.kind == .image {
                    try await Task.detached {
                        let image = try self.imageRenderer.render(
                            contentURL: capture.url,
                            frameURL: frameURL,
                            frame: frame,
                            settings: currentSettings
                        )
                        try self.imageRenderer.writePNG(image, to: destination)
                    }.value
                    exportProgress = 1
                } else {
                    let job = VideoRenderJob()
                    currentVideoJob = job
                    try await videoRenderer.render(
                        sourceURL: capture.url,
                        destinationURL: destination,
                        frameURL: frameURL,
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
        guard capture?.kind == .image, let previewImage else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([previewImage])
        statusMessage = "Copied framed image to the clipboard."
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
            manifest = try await libraryService.loadManifest()
            selectedFrameID = UserDefaults.standard.string(forKey: "lastFrameID")
            if selectedFrame == nil { selectedFrameID = manifest?.frames.first?.id }
            settings.frameID = selectedFrameID
            if let manifest {
                statusMessage = "\(manifest.frames.count) device frames ready. Drop a capture to begin."
                await loadSelectedFrameImage()
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
        Task {
            await loadSelectedFrameImage()
            refreshPreview()
        }
        if capture.kind == .video {
            statusMessage = detection?.isAmbiguous == true ? "Video ready · choose the correct device." : "Video ready."
        } else if detection?.isAmbiguous == true {
            statusMessage = "Multiple devices share this resolution · choose the correct device."
        }
    }

    private func loadSelectedFrameImage() async {
        guard let frame = selectedFrame else {
            selectedFrameImage = nil
            return
        }
        let url = await libraryService.frameURL(for: frame)
        selectedFrameImage = NSImage(contentsOf: url)
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        statusMessage = "Action failed."
        AppLog.app.error("\(error.localizedDescription, privacy: .public)")
    }
}
