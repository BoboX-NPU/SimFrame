import AppKit
import CoreGraphics
import Foundation

enum FrameOrientation: String, Codable, CaseIterable, Identifiable, Sendable {
    case portrait
    case landscape

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct DeviceFrame: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var device: String
    var variant: String
    var orientation: FrameOrientation
    var frameFile: String
    var canvasSize: CGSize
    var screenRect: CGRect
    var normalizedScreenRect: CGRect
    var expectedCaptureSizes: [CGSize]

    var displayName: String { "\(device) · \(variant)" }
}

struct FrameLibraryManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var displayName: String
    var importedAt: Date
    var frames: [DeviceFrame]
}

enum CaptureKind: String, Codable, Sendable {
    case image
    case video
}

struct CaptureDescriptor: Identifiable, Equatable, Sendable {
    var id: URL { url }
    var url: URL
    var kind: CaptureKind
    var pixelSize: CGSize
    var duration: TimeInterval
    var nominalFrameRate: Double
    var hasAudio: Bool

    var displayName: String { url.deletingPathExtension().lastPathComponent }
    var orientation: FrameOrientation {
        pixelSize.width > pixelSize.height ? .landscape : .portrait
    }
}

struct DetectionCandidate: Identifiable, Equatable, Sendable {
    var id: String { frame.id }
    var frame: DeviceFrame
    var score: Int
    var reasons: [String]
}

struct DetectionResult: Equatable, Sendable {
    var candidates: [DetectionCandidate]
    var isAmbiguous: Bool

    var best: DetectionCandidate? { candidates.first }
}

enum CanvasPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case original
    case balanced
    case spacious

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var paddingFraction: CGFloat {
        switch self {
        case .original: 0
        case .balanced: 0.08
        case .spacious: 0.16
        }
    }
    var hasShadow: Bool { self != .original }
}

struct RGBAColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let black = RGBAColor(red: 0.04, green: 0.045, blue: 0.055, alpha: 1)
    static let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? .black
        red = converted.redComponent
        green = converted.greenComponent
        blue = converted.blueComponent
        alpha = converted.alphaComponent
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

enum BackgroundMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case transparent
    case solid

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct RenderBackground: Codable, Equatable, Sendable {
    var mode: BackgroundMode
    var color: RGBAColor

    static let transparent = RenderBackground(mode: .transparent, color: .black)
    static let dark = RenderBackground(mode: .solid, color: .black)
}

enum ExportFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case png
    case mov
    case mp4

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

struct RenderSettings: Codable, Equatable, Sendable {
    var frameID: String?
    var background: RenderBackground = .transparent
    var canvasPreset: CanvasPreset = .original
    var exportFormat: ExportFormat = .png
}

struct RecentCaptureRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var bookmark: Data
    var kind: CaptureKind
    var lastOpenedAt: Date
}

struct FrameImportReport: Sendable {
    var manifest: FrameLibraryManifest
    var skippedFiles: [String]
}

enum FrameImportPhase: Equatable, Sendable {
    case scanning
    case processing(completed: Int, total: Int)
    case installing
    case loadingSelection
    case cancelling

    var isCancellable: Bool {
        switch self {
        case .scanning, .processing:
            true
        case .installing, .loadingSelection, .cancelling:
            false
        }
    }

    var detailText: String {
        switch self {
        case .scanning:
            "Scanning frame folder…"
        case let .processing(completed, total):
            "Preparing device frame \(completed) of \(total)…"
        case .installing:
            "Installing device frame library…"
        case .loadingSelection:
            "Loading first device frame…"
        case .cancelling:
            "Cancelling import…"
        }
    }

    var fractionCompleted: Double? {
        switch self {
        case let .processing(completed, total):
            guard total > 0 else { return 0 }
            return min(max(Double(completed) / Double(total), 0), 1)
        case .installing, .loadingSelection:
            return 1
        case .scanning, .cancelling:
            return nil
        }
    }
}

struct FrameRenderAssets: @unchecked Sendable {
    let artwork: CGImage
    let screenMask: CGImage

    var decodedByteCost: Int {
        artwork.bytesPerRow * artwork.height + screenMask.bytesPerRow * screenMask.height
    }
}

enum SimFrameError: LocalizedError, Equatable {
    case unsupportedFile
    case missingVideoTrack
    case noUsableFrames
    case invalidFrame(String)
    case noSelection
    case mp4RequiresOpaqueBackground
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: "Choose a PNG, JPEG, HEIC, MOV, or MP4 capture."
        case .missingVideoTrack: "The selected movie does not contain a video track."
        case .noUsableFrames: "No usable transparent PNG device frames were found."
        case let .invalidFrame(reason): "The frame could not be imported: \(reason)"
        case .noSelection: "Choose a capture and device frame first."
        case .mp4RequiresOpaqueBackground: "MP4 export requires a solid background."
        case let .exportFailed(reason): "Export failed: \(reason)"
        }
    }
}
