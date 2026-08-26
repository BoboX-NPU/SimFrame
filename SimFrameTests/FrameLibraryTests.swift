import Foundation
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

        do {
            _ = try await service.importLibrary(from: invalid)
            XCTFail("Expected an empty import to fail")
        } catch {
            XCTAssertEqual(error as? SimFrameError, .noUsableFrames)
        }
        let retained = try await service.loadManifest()
        XCTAssertEqual(retained?.frames.count, 1)
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
}

