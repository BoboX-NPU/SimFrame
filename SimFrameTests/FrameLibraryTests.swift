import Foundation
import ImageIO
import XCTest
@testable import SimFrame

final class FrameLibraryTests: XCTestCase {
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
