import Foundation
import ImageIO
import XCTest
@testable import SimFrame

final class FrameLibraryTests: XCTestCase {
    func testImportReportsScanningMonotonicProcessingAndInstalling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("Source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try TestImageFactory.writeFrame(to: source.appendingPathComponent("Test Phone - Black - Portrait.png"))
        try TestImageFactory.writeFrame(to: source.appendingPathComponent("Test Phone - Silver - Portrait.png"))
        try Data("not a png".utf8).write(
            to: source.appendingPathComponent("Broken Phone - Black - Portrait.png")
        )
        let recorder = ImportPhaseRecorder()
        let service = FrameLibraryService(baseDirectory: root.appendingPathComponent("Support"))

        let report = try await service.importLibrary(from: source) { phase in
            await recorder.append(phase)
        }

        let phases = await recorder.values
        XCTAssertEqual(phases.first, .scanning)
        XCTAssertEqual(phases.last, .installing)
        let processing = phases.compactMap { phase -> (Int, Int)? in
            guard case let .processing(completed, total) = phase else { return nil }
            return (completed, total)
        }
        XCTAssertEqual(processing.map(\.0), [0, 1, 2, 3])
        XCTAssertEqual(processing.map(\.1), [3, 3, 3, 3])
        XCTAssertEqual(report.manifest.frames.count, 2)
        XCTAssertEqual(report.skippedFiles.count, 1)
    }

    func testCancelledReplacementKeepsExistingLibraryAndRemovesStaging() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let oldSource = root.appendingPathComponent("Old")
        let replacement = root.appendingPathComponent("Replacement")
        let support = root.appendingPathComponent("Support")
        try FileManager.default.createDirectory(at: oldSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try TestImageFactory.writeFrame(to: oldSource.appendingPathComponent("Old Phone - Black - Portrait.png"))
        try TestImageFactory.writeFrame(to: replacement.appendingPathComponent("New Phone - Black - Portrait.png"))
        try TestImageFactory.writeFrame(to: replacement.appendingPathComponent("New Phone - Silver - Portrait.png"))
        try TestImageFactory.writeFrame(to: replacement.appendingPathComponent("New Phone - White - Portrait.png"))
        let service = FrameLibraryService(baseDirectory: support)
        let original = try await service.importLibrary(from: oldSource)
        let manifestURL = support.appendingPathComponent("FrameLibrary/manifest.json")
        let originalManifestData = try Data(contentsOf: manifestURL)
        let originalFrame = try XCTUnwrap(original.manifest.frames.first)
        let originalMaskURL = support.appendingPathComponent("FrameLibrary/Masks/\(originalFrame.id).png")
        let originalMaskData = try Data(contentsOf: originalMaskURL)

        do {
            _ = try await service.importLibrary(from: replacement) { phase in
                if phase == .processing(completed: 1, total: 3) {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            XCTFail("Expected replacement import to be cancelled")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: manifestURL), originalManifestData)
        XCTAssertEqual(try Data(contentsOf: originalMaskURL), originalMaskData)
        let supportContents = try FileManager.default.contentsOfDirectory(
            at: support,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(supportContents.contains { $0.lastPathComponent.hasPrefix(".FrameLibrary-") })
    }

    func testTransparentOpeningIsDetected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Test Phone - Black - Portrait.png")
        try TestImageFactory.writeFrame(to: url)

        let frame = try FrameScanner.scan(url: url)
        XCTAssertEqual(frame.device, "Test Phone")
        XCTAssertEqual(frame.variant, "Black")
        XCTAssertEqual(frame.orientation, .portrait)
        XCTAssertEqual(frame.screenRect, CGRect(x: 20, y: 40, width: 320, height: 640))
        XCTAssertEqual(frame.expectedCaptureSizes, [CGSize(width: 320, height: 640)])
    }

    func testCompactAlphaAnalysisFeedsFrameMetadataAndMask() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Test Phone - Black - Portrait.png")
        try TestImageFactory.writeFrame(to: url, screenCornerRadius: 48)
        let image = TestImageFactory.image(at: url)

        let analysis = try FrameScanner.analyze(image: image)
        let frame = try FrameScanner.scan(url: url, analysis: analysis)
        let mask = try CompositionRenderer.makeScreenMask(analysis: analysis, frame: frame)

        let pixelCount = image.width * image.height
        XCTAssertEqual(analysis.alpha.count, pixelCount)
        XCTAssertEqual(analysis.aperture.count, pixelCount)
        XCTAssertEqual(frame.screenRect, analysis.screenRect)
        XCTAssertEqual(mask.width, Int(frame.screenRect.width))
        XCTAssertEqual(mask.height, Int(frame.screenRect.height))
    }

    func testImportAndFailedReplacementKeepsExistingLibrary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let valid = root.appendingPathComponent("Valid")
        let invalid = root.appendingPathComponent("Invalid")
        try FileManager.default.createDirectory(at: valid, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try TestImageFactory.writeFrame(to: valid.appendingPathComponent("Test Phone - Black - Portrait.png"))

        let service = FrameLibraryService(baseDirectory: root.appendingPathComponent("Support"))
        let first = try await service.importLibrary(from: valid)
        XCTAssertEqual(first.manifest.frames.count, 1)
        let firstFrame = try XCTUnwrap(first.manifest.frames.first)
        let maskURL = root.appendingPathComponent("Support/FrameLibrary/Masks/\(firstFrame.id).png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: maskURL.path))

        do {
            _ = try await service.importLibrary(from: invalid)
            XCTFail("Expected an empty import to fail")
        } catch {
            XCTAssertEqual(error as? SimFrameError, .noUsableFrames)
        }
        let retained = try await service.loadManifest()
        XCTAssertEqual(retained?.frames.count, 1)
        XCTAssertNotNil(CGImageSourceCreateWithURL(maskURL as CFURL, nil))
    }

    func testExistingLibraryRepairsMissingAndCorruptMasks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("Source")
        let support = root.appendingPathComponent("Support")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try TestImageFactory.writeFrame(to: source.appendingPathComponent("Test Phone - Black - Portrait.png"))

        let importer = FrameLibraryService(baseDirectory: support)
        let report = try await importer.importLibrary(from: source)
        let frame = try XCTUnwrap(report.manifest.frames.first)
        let maskURL = support.appendingPathComponent("FrameLibrary/Masks/\(frame.id).png")
        try FileManager.default.removeItem(at: maskURL)

        let missingMaskLoader = FrameLibraryService(baseDirectory: support)
        _ = try await missingMaskLoader.loadManifest()
        XCTAssertNotNil(CGImageSourceCreateWithURL(maskURL as CFURL, nil))

        try Data("corrupt".utf8).write(to: maskURL, options: .atomic)
        let corruptMaskLoader = FrameLibraryService(baseDirectory: support)
        _ = try await corruptMaskLoader.loadManifest()
        let repairedSource = try XCTUnwrap(CGImageSourceCreateWithURL(maskURL as CFURL, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(repairedSource, 0, nil))

        try TestImageFactory.writeCapture(to: maskURL, size: CGSize(width: 10, height: 10))
        let wrongSizeMaskLoader = FrameLibraryService(baseDirectory: support)
        _ = try await wrongSizeMaskLoader.loadManifest()
        let repairedAssets = try await wrongSizeMaskLoader.assets(for: frame)
        XCTAssertEqual(repairedAssets.screenMask.width, Int(frame.screenRect.width))
        XCTAssertEqual(repairedAssets.screenMask.height, Int(frame.screenRect.height))
    }

    func testFrameAssetsReuseDecodedMemoryCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("Source")
        let support = root.appendingPathComponent("Support")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try TestImageFactory.writeFrame(to: source.appendingPathComponent("Test Phone - Black - Portrait.png"))

        let service = FrameLibraryService(baseDirectory: support)
        let report = try await service.importLibrary(from: source)
        let frame = try XCTUnwrap(report.manifest.frames.first)
        let first = try await service.assets(for: frame)
        let second = try await service.assets(for: frame)

        XCTAssertTrue(first.artwork === second.artwork)
        XCTAssertTrue(first.screenMask === second.screenMask)
    }

    func testLocalIPhone17PackScansThirtyFramesWhenPresent() throws {
        let root = URL(fileURLWithPath: "/Users/xuemingbo/Downloads/PNG-iPhone-17")
        guard FileManager.default.fileExists(atPath: root.path) else { throw XCTSkip("Local Apple frame pack is not present") }
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "png" }
        let frames = try files.map(FrameScanner.scan)
        XCTAssertEqual(frames.count, 30)
        XCTAssertEqual(Set(frames.map(\.device)), Set(["iPhone 17", "iPhone 17 Pro", "iPhone 17 Pro Max", "iPhone Air"]))
        let pro = try XCTUnwrap(frames.first { $0.device == "iPhone 17 Pro" && $0.orientation == .portrait })
        XCTAssertEqual(pro.canvasSize, CGSize(width: 1350, height: 2760))
        XCTAssertEqual(pro.screenRect, CGRect(x: 72, y: 69, width: 1206, height: 2622))
    }

    func testLocalIPhone17PackImportsThirtyFramesWhenPresent() async throws {
        guard ProcessInfo.processInfo.environment["SIMFRAME_RUN_IMPORT_PERFORMANCE_TEST"] == "1" else {
            throw XCTSkip("Set SIMFRAME_RUN_IMPORT_PERFORMANCE_TEST=1 to run the local 30-frame import benchmark")
        }
        let source = URL(fileURLWithPath: "/Users/xuemingbo/Downloads/PNG-iPhone-17")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("Local Apple frame pack is not present")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FrameLibraryService(baseDirectory: root.appendingPathComponent("Support"))
        let start = ContinuousClock.now

        let report = try await service.importLibrary(from: source)

        let elapsed = start.duration(to: .now)
        XCTAssertEqual(report.manifest.frames.count, 30)
        let masks = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Support/FrameLibrary/Masks"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(masks.filter { $0.pathExtension == "png" }.count, 30)
        print("Optimized 30-frame import duration: \(elapsed)")
    }
}

@MainActor
final class FrameImportStateTests: XCTestCase {
    func testImportBlocksDuplicateRequestsAndWaitsForFirstFrameAssets() async throws {
        let frame = makeFrame(id: "new-phone-black")
        let manifest = makeManifest(frame: frame)
        let assets = try makeAssets()
        let service = ControlledFrameLibraryService(
            initialManifest: nil,
            importedManifest: manifest,
            assets: assets,
            behavior: .complete(assetDelay: 0.2)
        )
        let state = AppState(libraryService: service)
        try await Task.sleep(for: .milliseconds(20))

        state.importFrameLibrary(from: URL(fileURLWithPath: "/tmp/first-library"))
        state.importFrameLibrary(from: URL(fileURLWithPath: "/tmp/duplicate-library"))

        XCTAssertTrue(state.isImportingFrames)
        try await waitUntil { state.frameImportPhase == .loadingSelection }
        XCTAssertTrue(state.isImportingFrames)
        XCTAssertFalse(state.canCancelFrameImport)
        XCTAssertNil(state.selectedFrameImage)
        let importCallCount = await service.importCallCount
        XCTAssertEqual(importCallCount, 1)

        try await waitUntil { !state.isImportingFrames }
        XCTAssertEqual(state.manifest, manifest)
        XCTAssertNotNil(state.selectedFrameImage)
        XCTAssertNotNil(state.selectedFrameMaskImage)
        XCTAssertEqual(state.statusMessage, "Imported 1 device frames.")
    }

    func testCancellationIgnoresLateProgressAndKeepsExistingManifest() async throws {
        let oldFrame = makeFrame(id: "old-phone-black")
        let oldManifest = makeManifest(frame: oldFrame)
        let service = ControlledFrameLibraryService(
            initialManifest: oldManifest,
            importedManifest: makeManifest(frame: makeFrame(id: "new-phone-black")),
            assets: try makeAssets(),
            behavior: .waitForCancellation
        )
        let state = AppState(libraryService: service)
        try await waitUntil { state.manifest == oldManifest }

        state.importFrameLibrary(from: URL(fileURLWithPath: "/tmp/replacement-library"))
        try await waitUntil { state.frameImportPhase == .processing(completed: 0, total: 2) }
        state.importFrameLibrary(from: URL(fileURLWithPath: "/tmp/duplicate-library"))
        let importCallCount = await service.importCallCount
        XCTAssertEqual(importCallCount, 1)

        state.cancelFrameImport()
        XCTAssertEqual(state.frameImportPhase, .cancelling)
        XCTAssertFalse(state.canCancelFrameImport)
        try await waitUntil { !state.isImportingFrames }

        XCTAssertEqual(state.manifest, oldManifest)
        XCTAssertEqual(state.statusMessage, "Import cancelled. Existing device frames were kept.")
        XCTAssertNil(state.errorMessage)
    }

    func testFirstFrameAssetFailureEndsImportAndPresentsError() async throws {
        let frame = makeFrame(id: "broken-phone-black")
        let manifest = makeManifest(frame: frame)
        let service = ControlledFrameLibraryService(
            initialManifest: nil,
            importedManifest: manifest,
            assets: try makeAssets(),
            behavior: .failAssets
        )
        let state = AppState(libraryService: service)
        try await Task.sleep(for: .milliseconds(20))

        state.importFrameLibrary(from: URL(fileURLWithPath: "/tmp/broken-library"))
        try await waitUntil { state.errorMessage != nil }

        XCTAssertFalse(state.isImportingFrames)
        XCTAssertNil(state.frameImportPhase)
        XCTAssertEqual(state.manifest, manifest)
        XCTAssertNil(state.selectedFrameImage)
        XCTAssertNil(state.selectedFrameMaskImage)
        XCTAssertEqual(state.statusMessage, "Action failed.")
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for AppState")
    }

    private func makeFrame(id: String) -> DeviceFrame {
        DeviceFrame(
            id: id,
            device: "Test Phone",
            variant: "Black",
            orientation: .portrait,
            frameFile: "Frames/\(id).png",
            canvasSize: CGSize(width: 360, height: 720),
            screenRect: CGRect(x: 20, y: 40, width: 320, height: 640),
            normalizedScreenRect: CGRect(x: 20.0 / 360, y: 40.0 / 720, width: 320.0 / 360, height: 640.0 / 720),
            expectedCaptureSizes: [CGSize(width: 320, height: 640)]
        )
    }

    private func makeManifest(frame: DeviceFrame) -> FrameLibraryManifest {
        FrameLibraryManifest(
            schemaVersion: FrameLibraryManifest.currentSchemaVersion,
            displayName: "Test Library",
            importedAt: Date(timeIntervalSince1970: 1),
            frames: [frame]
        )
    }

    private func makeAssets() throws -> FrameRenderAssets {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Test Phone - Black - Portrait.png")
        try TestImageFactory.writeFrame(to: url)
        let image = TestImageFactory.image(at: url)
        return FrameRenderAssets(artwork: image, screenMask: image)
    }
}

private actor ImportPhaseRecorder {
    private(set) var values: [FrameImportPhase] = []

    func append(_ phase: FrameImportPhase) {
        values.append(phase)
    }
}

private actor ControlledFrameLibraryService: FrameLibraryServing {
    enum Behavior: Sendable {
        case complete(assetDelay: TimeInterval)
        case failAssets
        case waitForCancellation
    }

    private let initialManifest: FrameLibraryManifest?
    private let importedManifest: FrameLibraryManifest
    private let assetsValue: FrameRenderAssets
    private let behavior: Behavior
    private(set) var importCallCount = 0

    init(
        initialManifest: FrameLibraryManifest?,
        importedManifest: FrameLibraryManifest,
        assets: FrameRenderAssets,
        behavior: Behavior
    ) {
        self.initialManifest = initialManifest
        self.importedManifest = importedManifest
        assetsValue = assets
        self.behavior = behavior
    }

    func loadManifest() throws -> FrameLibraryManifest? {
        initialManifest
    }

    func assets(for frame: DeviceFrame) throws -> FrameRenderAssets {
        switch behavior {
        case let .complete(assetDelay):
            Thread.sleep(forTimeInterval: assetDelay)
            return assetsValue
        case .failAssets:
            throw CocoaError(.fileReadCorruptFile)
        case .waitForCancellation:
            return assetsValue
        }
    }

    func importLibrary(
        from sourceDirectory: URL,
        progress: FrameImportProgressHandler
    ) async throws -> FrameImportReport {
        importCallCount += 1
        await progress(.scanning)
        await progress(.processing(completed: 0, total: 2))
        switch behavior {
        case .complete, .failAssets:
            await progress(.processing(completed: 1, total: 2))
            await progress(.processing(completed: 2, total: 2))
            await progress(.installing)
            return FrameImportReport(manifest: importedManifest, skippedFiles: [])
        case .waitForCancellation:
            do {
                try await Task.sleep(for: .seconds(30))
                return FrameImportReport(manifest: importedManifest, skippedFiles: [])
            } catch {
                await progress(.processing(completed: 1, total: 2))
                throw error
            }
        }
    }
}
