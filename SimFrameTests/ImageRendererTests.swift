import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import SimFrame

final class ImageRendererTests: XCTestCase {
    func testPNGExportReplacesExistingDestinationAfterRendering() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appendingPathComponent("Test Phone - Black - Portrait.png")
        let contentURL = directory.appendingPathComponent("capture.png")
        let destinationURL = directory.appendingPathComponent("existing.png")
        try TestImageFactory.writeFrame(to: frameURL)
        try TestImageFactory.writeCapture(to: contentURL)
        try Data("old contents".utf8).write(to: destinationURL)
        let frame = try FrameScanner.scan(url: frameURL)
        let renderer = ImageRenderer()
        let image = try renderer.render(
            contentURL: contentURL,
            frameURL: frameURL,
            frame: frame,
            settings: RenderSettings(frameID: frame.id)
        )

        try renderer.writePNG(image, to: destinationURL)

        XCTAssertNotNil(CGImageSourceCreateWithURL(destinationURL as CFURL, nil))
    }

    func testOriginalCanvasAndTransparentCorners() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appendingPathComponent("Test Phone - Black - Portrait.png")
        let contentURL = directory.appendingPathComponent("capture.png")
        try TestImageFactory.writeFrame(to: frameURL)
        try TestImageFactory.writeCapture(to: contentURL)
        let frame = try FrameScanner.scan(url: frameURL)

        let image = try ImageRenderer().render(
            contentURL: contentURL,
            frameURL: frameURL,
            frame: frame,
            settings: RenderSettings(frameID: frame.id)
        )
        XCTAssertEqual(image.width, 360)
        XCTAssertEqual(image.height, 720)
        XCTAssertEqual(alpha(image, x: 0, y: 0), 255)
        XCTAssertGreaterThan(blue(image, x: 100, y: 100), 180)
    }

    func testBalancedCanvasAddsPadding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appendingPathComponent("Test Phone - Black - Portrait.png")
        let contentURL = directory.appendingPathComponent("capture.png")
        try TestImageFactory.writeFrame(to: frameURL)
        try TestImageFactory.writeCapture(to: contentURL)
        let frame = try FrameScanner.scan(url: frameURL)
        var settings = RenderSettings(frameID: frame.id)
        settings.canvasPreset = .balanced

        let image = try ImageRenderer().render(contentURL: contentURL, frameURL: frameURL, frame: frame, settings: settings)
        XCTAssertEqual(image.width, 418)
        XCTAssertEqual(image.height, 836)
        XCTAssertEqual(alpha(image, x: 0, y: 0), 0)
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        let data = image.dataProvider!.data!
        return Array(UnsafeBufferPointer(start: CFDataGetBytePtr(data), count: CFDataGetLength(data)))
    }

    private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        bytes(image)[y * image.bytesPerRow + x * 4 + 3]
    }

    private func blue(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        bytes(image)[y * image.bytesPerRow + x * 4 + 2]
    }
}
