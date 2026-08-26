import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor FrameLibraryService {
    private let fileManager: FileManager
    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else if let override = ProcessInfo.processInfo.environment["SIMFRAME_APP_SUPPORT"], !override.isEmpty {
            self.baseDirectory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = support.appendingPathComponent("SimFrame", isDirectory: true)
        }
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    var libraryDirectory: URL {
        baseDirectory.appendingPathComponent("FrameLibrary", isDirectory: true)
    }

    func loadManifest() throws -> FrameLibraryManifest? {
        let url = libraryDirectory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(FrameLibraryManifest.self, from: Data(contentsOf: url))
    }

    func frameURL(for frame: DeviceFrame) -> URL {
        libraryDirectory.appendingPathComponent(frame.frameFile)
    }

    func importLibrary(from sourceDirectory: URL) throws -> FrameImportReport {
        let accessed = sourceDirectory.startAccessingSecurityScopedResource()
        defer { if accessed { sourceDirectory.stopAccessingSecurityScopedResource() } }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let staging = baseDirectory.appendingPathComponent(".FrameLibrary-\(UUID().uuidString)", isDirectory: true)
        let framesDirectory = staging.appendingPathComponent("Frames", isDirectory: true)
        try fileManager.createDirectory(at: framesDirectory, withIntermediateDirectories: true)

        do {
            let candidates = try pngFiles(in: sourceDirectory)
            var frames: [DeviceFrame] = []
            var skipped: [String] = []
            var usedIDs = Set<String>()

            for source in candidates {
                do {
                    var frame = try FrameScanner.scan(url: source)
                    if usedIDs.contains(frame.id) {
                        frame = DeviceFrame(
                            id: "\(frame.id)-\(shortHash(source.path))",
                            device: frame.device,
                            variant: frame.variant,
                            orientation: frame.orientation,
                            frameFile: frame.frameFile,
                            canvasSize: frame.canvasSize,
                            screenRect: frame.screenRect,
                            normalizedScreenRect: frame.normalizedScreenRect,
                            expectedCaptureSizes: frame.expectedCaptureSizes
                        )
                    }
                    usedIDs.insert(frame.id)
                    let relativePath = "Frames/\(frame.id).png"
                    let destination = staging.appendingPathComponent(relativePath)
                    try fileManager.copyItem(at: source, to: destination)
                    frame.frameFile = relativePath
                    frames.append(frame)
                } catch {
                    skipped.append("\(source.lastPathComponent): \(error.localizedDescription)")
                }
            }

            guard !frames.isEmpty else { throw SimFrameError.noUsableFrames }
            frames.sort {
                [$0.device, $0.orientation.rawValue, $0.variant].joined(separator: "|") <
                    [$1.device, $1.orientation.rawValue, $1.variant].joined(separator: "|")
            }
            let manifest = FrameLibraryManifest(
                schemaVersion: FrameLibraryManifest.currentSchemaVersion,
                displayName: sourceDirectory.lastPathComponent,
                importedAt: Date(),
                frames: frames
            )
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            try install(staging: staging)
            AppLog.library.info("Imported \(frames.count) frame files")
            return FrameImportReport(manifest: manifest, skippedFiles: skipped)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    func saveUpdatedFrame(_ updated: DeviceFrame) throws -> FrameLibraryManifest {
        guard var manifest = try loadManifest(),
              let index = manifest.frames.firstIndex(where: { $0.id == updated.id }) else {
            throw SimFrameError.noUsableFrames
        }
        manifest.frames[index] = updated
        let data = try encoder.encode(manifest)
        try data.write(to: libraryDirectory.appendingPathComponent("manifest.json"), options: .atomic)
        return manifest
    }

    private func pngFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension.lowercased() == "png" else { return nil }
            return url
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func install(staging: URL) throws {
        let destination = libraryDirectory
        let backup = baseDirectory.appendingPathComponent(".FrameLibrary-backup-\(UUID().uuidString)")
        let hadExisting = fileManager.fileExists(atPath: destination.path)
        if hadExisting { try fileManager.moveItem(at: destination, to: backup) }
        do {
            try fileManager.moveItem(at: staging, to: destination)
            if hadExisting { try? fileManager.removeItem(at: backup) }
        } catch {
            if hadExisting, fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    private func shortHash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

enum FrameScanner {
    static func scan(url: URL) throws -> DeviceFrame {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SimFrameError.invalidFrame("Unreadable PNG")
        }
        guard image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast else {
            throw SimFrameError.invalidFrame("The PNG has no alpha channel")
        }
        let parsed = try parseFilename(url.deletingPathExtension().lastPathComponent)
        let screenRect = try transparentScreenRect(in: image)
        let canvasSize = CGSize(width: image.width, height: image.height)
        let normalized = CGRect(
            x: screenRect.minX / canvasSize.width,
            y: screenRect.minY / canvasSize.height,
            width: screenRect.width / canvasSize.width,
            height: screenRect.height / canvasSize.height
        )
        let identifier = slug("\(parsed.device)-\(parsed.variant)-\(parsed.orientation.rawValue)")
        return DeviceFrame(
            id: identifier,
            device: parsed.device,
            variant: parsed.variant,
            orientation: parsed.orientation,
            frameFile: url.lastPathComponent,
            canvasSize: canvasSize,
            screenRect: screenRect,
            normalizedScreenRect: normalized,
            expectedCaptureSizes: [screenRect.size]
        )
    }

    static func transparentScreenRect(in image: CGImage) throws -> CGRect {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SimFrameError.invalidFrame("Unable to inspect alpha channel") }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let threshold: UInt8 = 8
        let centerX = width / 2
        let centerY = height / 2
        var seed: Int?
        let maxRadius = min(width, height) / 4
        for radius in 0...maxRadius where seed == nil {
            let points = [
                (centerX + radius, centerY), (centerX - radius, centerY),
                (centerX, centerY + radius), (centerX, centerY - radius)
            ]
            for (x, y) in points where x >= 0 && x < width && y >= 0 && y < height {
                if pixels[y * bytesPerRow + x * 4 + 3] <= threshold {
                    seed = y * width + x
                    break
                }
            }
        }
        guard let seed else { throw SimFrameError.invalidFrame("No transparent screen opening near the center") }

        var visited = [UInt8](repeating: 0, count: width * height)
        var queue = [Int]()
        queue.reserveCapacity(width * height / 2)
        queue.append(seed)
        visited[seed] = 1
        var cursor = 0
        var minX = width, minY = height, maxX = 0, maxY = 0, area = 0
        var touchesEdge = false

        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            area += 1
            if x == 0 || y == 0 || x == width - 1 || y == height - 1 { touchesEdge = true }

            if x > 0 {
                let neighbor = index - 1
                if visited[neighbor] == 0, pixels[y * bytesPerRow + (x - 1) * 4 + 3] <= threshold {
                    visited[neighbor] = 1; queue.append(neighbor)
                }
            }
            if x + 1 < width {
                let neighbor = index + 1
                if visited[neighbor] == 0, pixels[y * bytesPerRow + (x + 1) * 4 + 3] <= threshold {
                    visited[neighbor] = 1; queue.append(neighbor)
                }
            }
            if y > 0 {
                let neighbor = index - width
                if visited[neighbor] == 0, pixels[(y - 1) * bytesPerRow + x * 4 + 3] <= threshold {
                    visited[neighbor] = 1; queue.append(neighbor)
                }
            }
            if y + 1 < height {
                let neighbor = index + width
                if visited[neighbor] == 0, pixels[(y + 1) * bytesPerRow + x * 4 + 3] <= threshold {
                    visited[neighbor] = 1; queue.append(neighbor)
                }
            }
        }

        let minimumArea = width * height / 4
        guard !touchesEdge, area > minimumArea else {
            throw SimFrameError.invalidFrame("The central transparent region is not a closed screen opening")
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func parseFilename(_ name: String) throws -> (device: String, variant: String, orientation: FrameOrientation) {
        let pieces = name.components(separatedBy: " - ")
        guard pieces.count >= 3, let orientationText = pieces.last else {
            throw SimFrameError.invalidFrame("Expected ‘Device - Variant - Portrait.png’ naming")
        }
        let orientation: FrameOrientation
        switch orientationText.lowercased() {
        case "portrait": orientation = .portrait
        case "landscape": orientation = .landscape
        default: throw SimFrameError.invalidFrame("Filename must end in Portrait or Landscape")
        }
        let variant = pieces[pieces.count - 2]
        let device = pieces.dropLast(2).joined(separator: " - ")
        return (device, variant, orientation)
    }

    private static func slug(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
