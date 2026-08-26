import CoreGraphics
import CoreImage
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

    func testRoundedScreenMaskClipsCompositedCaptureCorners() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appendingPathComponent("Rounded Phone - Black - Portrait.png")
        try TestImageFactory.writeFrame(to: frameURL, screenCornerRadius: 48)
        let frame = try FrameScanner.scan(url: frameURL)
        let geometry = CompositionGeometry(frame: frame, preset: .original)
        let frameImage = try XCTUnwrap(CIImage(contentsOf: frameURL))
        let prepared = CompositionRenderer.prepareFrame(frameImage, geometry: geometry)
        let screenBounds = geometry.coreImageRect(fromTopLeft: geometry.screenRect)
        let maskImage = try XCTUnwrap(CIContext().createCGImage(prepared.apertureMask, from: screenBounds))
        let previewMask = try ImageRenderer().screenApertureMask(frameURL: frameURL, frame: frame)

        XCTAssertLessThan(alpha(maskImage, x: 2, y: 2), 8)
        XCTAssertGreaterThan(alpha(maskImage, x: maskImage.width / 2, y: maskImage.height / 2), 247)
        XCTAssertEqual(previewMask.size, frame.screenRect.size)

        let transparentArtwork = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: prepared.artwork.extent)
        let maskOnlyFrame = CompositionRenderer.PreparedFrame(
            artwork: transparentArtwork,
            apertureMask: prepared.apertureMask
        )
        let content = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: frame.screenRect.size))
        let output = CompositionRenderer.composite(
            content: content,
            preparedFrame: maskOnlyFrame,
            geometry: geometry,
            background: .transparent
        )
        let outputBounds = CGRect(origin: .zero, size: geometry.outputSize)
        let outputImage = try XCTUnwrap(CIContext().createCGImage(output, from: outputBounds))
        let cornerX = Int(geometry.screenRect.minX) + 2
        let cornerY = Int(geometry.screenRect.minY) + 2
        XCTAssertLessThan(alpha(outputImage, x: cornerX, y: cornerY), 8)
        XCTAssertGreaterThan(
            alpha(outputImage, x: Int(geometry.screenRect.midX), y: Int(geometry.screenRect.midY)),
            247
        )
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
