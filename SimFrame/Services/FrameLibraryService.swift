import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

typealias FrameImportProgressHandler = @Sendable (FrameImportPhase) async -> Void

protocol FrameLibraryServing: Actor {
    func loadManifest() throws -> FrameLibraryManifest?
    func assets(for frame: DeviceFrame) throws -> FrameRenderAssets
    func importLibrary(
        from sourceDirectory: URL,
        progress: FrameImportProgressHandler
    ) async throws -> FrameImportReport
}

actor FrameLibraryService: FrameLibraryServing {
    private struct CacheEntry {
        let assets: FrameRenderAssets
        let cost: Int
        var lastAccess: UInt64
    }

    private static let assetCacheCostLimit = 128 * 1_024 * 1_024
    private let fileManager: FileManager
    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var assetCache: [String: CacheEntry] = [:]
    private var assetCacheCost = 0
    private var assetCacheAccessCounter: UInt64 = 0

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

    var masksDirectory: URL {
        libraryDirectory.appendingPathComponent("Masks", isDirectory: true)
    }

    func loadManifest() throws -> FrameLibraryManifest? {
        let url = libraryDirectory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let manifest = try decoder.decode(FrameLibraryManifest.self, from: Data(contentsOf: url))
        try ensureMasks(for: manifest)
        return manifest
    }

    func frameURL(for frame: DeviceFrame) -> URL {
        libraryDirectory.appendingPathComponent(frame.frameFile)
    }

    func maskURL(for frame: DeviceFrame) -> URL {
        masksDirectory.appendingPathComponent("\(frame.id).png")
    }

    func assets(for frame: DeviceFrame) throws -> FrameRenderAssets {
        if var cached = assetCache[frame.id] {
            assetCacheAccessCounter &+= 1
            cached.lastAccess = assetCacheAccessCounter
            assetCache[frame.id] = cached
            return cached.assets
        }
        let artwork = try loadImage(at: frameURL(for: frame), message: "Unable to decode the selected frame")
        let maskLocation = maskURL(for: frame)
        let mask: CGImage
        if let existing = validMask(at: maskLocation, for: frame) {
            mask = existing
        } else {
            mask = try CompositionRenderer.makeScreenMask(frameImage: artwork, frame: frame)
            try writeMask(mask, to: maskLocation)
        }
        let assets = FrameRenderAssets(artwork: artwork, screenMask: mask)
        cache(assets, for: frame.id)
        return assets
    }

    func importLibrary(
        from sourceDirectory: URL,
        progress: FrameImportProgressHandler = { _ in }
    ) async throws -> FrameImportReport {
        let accessed = sourceDirectory.startAccessingSecurityScopedResource()
        defer { if accessed { sourceDirectory.stopAccessingSecurityScopedResource() } }

        await progress(.scanning)
        try Task.checkCancellation()
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let staging = baseDirectory.appendingPathComponent(".FrameLibrary-\(UUID().uuidString)", isDirectory: true)
        let framesDirectory = staging.appendingPathComponent("Frames", isDirectory: true)
        try fileManager.createDirectory(at: framesDirectory, withIntermediateDirectories: true)

        do {
            let candidates = try pngFiles(in: sourceDirectory)
            try Task.checkCancellation()
            await progress(.processing(completed: 0, total: candidates.count))
            var frames: [DeviceFrame] = []
            var skipped: [String] = []
            var usedIDs = Set<String>()
            let masksDirectory = staging.appendingPathComponent("Masks", isDirectory: true)
            try fileManager.createDirectory(at: masksDirectory, withIntermediateDirectories: true)

            for (index, source) in candidates.enumerated() {
                try Task.checkCancellation()
                do {
                    let frame = try autoreleasepool { () throws -> DeviceFrame in
                        let artwork = try loadImage(
                            at: source,
                            message: "Unable to decode the selected frame"
                        )
                        let analysis = try FrameScanner.analyze(image: artwork)
                        var frame = try FrameScanner.scan(url: source, analysis: analysis)
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
                        let mask = try CompositionRenderer.makeScreenMask(
                            analysis: analysis,
                            frame: frame
                        )
                        try writeMask(
                            mask,
                            to: masksDirectory.appendingPathComponent("\(frame.id).png")
                        )
                        return frame
                    }
                    frames.append(frame)
                } catch {
                    skipped.append("\(source.lastPathComponent): \(error.localizedDescription)")
                }
                await progress(.processing(completed: index + 1, total: candidates.count))
                try Task.checkCancellation()
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
            try Task.checkCancellation()
            await progress(.installing)
            try Task.checkCancellation()
            try manifestData.write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            try install(staging: staging)
            clearAssetCache()
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
        let artwork = try loadImage(at: frameURL(for: updated), message: "Unable to decode the selected frame")
        let mask = try CompositionRenderer.makeScreenMask(frameImage: artwork, frame: updated)
        try writeMask(mask, to: maskURL(for: updated))
        manifest.frames[index] = updated
        let data = try encoder.encode(manifest)
        try data.write(to: libraryDirectory.appendingPathComponent("manifest.json"), options: .atomic)
        removeCachedAssets(for: updated.id)
        return manifest
    }

    private func ensureMasks(for manifest: FrameLibraryManifest) throws {
        try fileManager.createDirectory(at: masksDirectory, withIntermediateDirectories: true)
        for frame in manifest.frames {
            let destination = maskURL(for: frame)
            if validMask(at: destination, for: frame) != nil {
                continue
            }
            try autoreleasepool {
                let artwork = try loadImage(
                    at: frameURL(for: frame),
                    message: "Unable to decode the selected frame"
                )
                let mask = try CompositionRenderer.makeScreenMask(frameImage: artwork, frame: frame)
                try writeMask(mask, to: destination)
            }
        }
    }

    private func loadImage(at url: URL, message: String) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SimFrameError.invalidFrame(message)
        }
        return image
    }

    private func validMask(at url: URL, for frame: DeviceFrame) -> CGImage? {
        guard fileManager.fileExists(atPath: url.path),
              let image = try? loadImage(at: url, message: "Unable to decode the selected frame mask") else {
            return nil
        }
        let expected = frame.screenRect.integral.size
        guard image.width == Int(expected.width), image.height == Int(expected.height) else { return nil }
        return image
    }

    private func writeMask(_ image: CGImage, to destination: URL) throws {
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent)-\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporary) }
        guard let writer = CGImageDestinationCreateWithURL(
            temporary as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw SimFrameError.invalidFrame("Unable to create the selected frame mask")
        }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else {
            throw SimFrameError.invalidFrame("Unable to write the selected frame mask")
        }
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    private func cache(_ assets: FrameRenderAssets, for frameID: String) {
        removeCachedAssets(for: frameID)
        let cost = assets.decodedByteCost
        guard cost <= Self.assetCacheCostLimit else { return }
        assetCacheAccessCounter &+= 1
        assetCache[frameID] = CacheEntry(
            assets: assets,
            cost: cost,
            lastAccess: assetCacheAccessCounter
        )
        assetCacheCost += cost
        while assetCacheCost > Self.assetCacheCostLimit,
              let leastRecent = assetCache.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            removeCachedAssets(for: leastRecent)
        }
    }

    private func removeCachedAssets(for frameID: String) {
        guard let removed = assetCache.removeValue(forKey: frameID) else { return }
        assetCacheCost -= removed.cost
    }

    private func clearAssetCache() {
        assetCache.removeAll(keepingCapacity: true)
        assetCacheCost = 0
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
    struct AlphaAnalysis {
        let width: Int
        let height: Int
        let alpha: [UInt8]
        let aperture: [UInt8]
        let screenRect: CGRect
    }

    static func scan(url: URL) throws -> DeviceFrame {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SimFrameError.invalidFrame("Unreadable PNG")
        }
        return try scan(url: url, analysis: analyze(image: image))
    }

    static func scan(url: URL, analysis: AlphaAnalysis) throws -> DeviceFrame {
        let parsed = try parseFilename(url.deletingPathExtension().lastPathComponent)
        let screenRect = analysis.screenRect
        let canvasSize = CGSize(width: analysis.width, height: analysis.height)
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
        try analyze(image: image).screenRect
    }

    static func analyze(image: CGImage) throws -> AlphaAnalysis {
        guard image.alphaInfo != .none,
              image.alphaInfo != .noneSkipFirst,
              image.alphaInfo != .noneSkipLast else {
            throw SimFrameError.invalidFrame("The PNG has no alpha channel")
        }
        let width = image.width
        let height = image.height
        let (pixelCount, pixelCountOverflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0,
              height > 0,
              !pixelCountOverflow,
              pixelCount <= Int(Int32.max) else {
            throw SimFrameError.invalidFrame("Unable to inspect alpha channel")
        }
        var alpha = [UInt8](repeating: 0, count: pixelCount)
        guard let context = CGContext(
            data: &alpha,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
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
                if alpha[y * width + x] <= threshold {
                    seed = y * width + x
                    break
                }
            }
        }
        guard let seed else { throw SimFrameError.invalidFrame("No transparent screen opening near the center") }

        var aperture = [UInt8](repeating: 0, count: pixelCount)
        let stack = UnsafeMutablePointer<Int32>.allocate(capacity: pixelCount)
        defer { stack.deallocate() }
        var stackCount = 1
        stack[0] = Int32(seed)
        var minX = width, minY = height, maxX = 0, maxY = 0, area = 0
        var touchesEdge = false
        alpha.withUnsafeBufferPointer { alphaBuffer in
            aperture.withUnsafeMutableBufferPointer { apertureBuffer in
                let alphaPixels = alphaBuffer.baseAddress!
                let aperturePixels = apertureBuffer.baseAddress!
                aperturePixels[seed] = 1
                while stackCount > 0 {
                    stackCount -= 1
                    let index = Int(stack[stackCount])
                    let x = index % width
                    let y = index / width
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                    area += 1
                    if x == 0 || y == 0 || x == width - 1 || y == height - 1 {
                        touchesEdge = true
                    }

                    if x > 0 {
                        let neighbor = index - 1
                        if aperturePixels[neighbor] == 0, alphaPixels[neighbor] <= threshold {
                            aperturePixels[neighbor] = 1
                            stack[stackCount] = Int32(neighbor)
                            stackCount += 1
                        }
                    }
                    if x + 1 < width {
                        let neighbor = index + 1
                        if aperturePixels[neighbor] == 0, alphaPixels[neighbor] <= threshold {
                            aperturePixels[neighbor] = 1
                            stack[stackCount] = Int32(neighbor)
                            stackCount += 1
                        }
                    }
                    if y > 0 {
                        let neighbor = index - width
                        if aperturePixels[neighbor] == 0, alphaPixels[neighbor] <= threshold {
                            aperturePixels[neighbor] = 1
                            stack[stackCount] = Int32(neighbor)
                            stackCount += 1
                        }
                    }
                    if y + 1 < height {
                        let neighbor = index + width
                        if aperturePixels[neighbor] == 0, alphaPixels[neighbor] <= threshold {
                            aperturePixels[neighbor] = 1
                            stack[stackCount] = Int32(neighbor)
                            stackCount += 1
                        }
                    }
                }
            }
        }

        let minimumArea = pixelCount / 4
        guard !touchesEdge, area > minimumArea else {
            throw SimFrameError.invalidFrame("The central transparent region is not a closed screen opening")
        }
        return AlphaAnalysis(
            width: width,
            height: height,
            alpha: alpha,
            aperture: aperture,
            screenRect: CGRect(
                x: minX,
                y: minY,
                width: maxX - minX + 1,
                height: maxY - minY + 1
            )
        )
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
