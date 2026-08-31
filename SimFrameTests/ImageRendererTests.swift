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

    func testRoundedScreenMaskOverlapsUnderFrameWithoutLeakingIntoCorners() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appendingPathComponent("Rounded Phone - Black - Portrait.png")
        try TestImageFactory.writeFrame(to: frameURL, screenCornerRadius: 48)
        let frame = try FrameScanner.scan(url: frameURL)
        let geometry = CompositionGeometry(frame: frame, preset: .original)
        let artwork = TestImageFactory.image(at: frameURL)
        let assets = FrameRenderAssets(
            artwork: artwork,
            screenMask: try CompositionRenderer.makeScreenMask(frameImage: artwork, frame: frame)
        )
        let prepared = CompositionRenderer.prepareFrame(assets: assets, geometry: geometry)
        let screenBounds = geometry.coreImageRect(fromTopLeft: geometry.screenRect)
        let maskImage = try XCTUnwrap(CIContext().createCGImage(prepared.apertureMask, from: screenBounds))
        let previewMask = try ImageRenderer().screenApertureMask(frameURL: frameURL, frame: frame)

        XCTAssertLessThan(alpha(maskImage, x: 2, y: 2), 8)
        XCTAssertGreaterThan(alpha(maskImage, x: 13, y: 13), 247)
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
        let overlapX = Int(geometry.screenRect.minX) + 13
        let overlapY = Int(geometry.screenRect.minY) + 13
        XCTAssertGreaterThan(alpha(outputImage, x: overlapX, y: overlapY), 247)
        XCTAssertGreaterThan(
            alpha(outputImage, x: Int(geometry.screenRect.midX), y: Int(geometry.screenRect.midY)),
            247
        )
    }

    func testScreenMaskFillsDynamicIslandWhileArtworkStillCoversIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appendingPathComponent("Island Phone - Black - Portrait.png")
        let island = CGRect(x: 145, y: 70, width: 70, height: 24)
        try TestImageFactory.writeFrame(
            to: frameURL,
            screenCornerRadius: 48,
            screenOcclusions: [island]
        )
        let frame = try FrameScanner.scan(url: frameURL)
        let artwork = TestImageFactory.image(at: frameURL)
        let sourceIslandPixel = rgbaAtTopLeft(artwork, x: Int(island.midX), y: Int(island.midY))
        XCTAssertLessThan(sourceIslandPixel.red, 32)
        let mask = try CompositionRenderer.makeScreenMask(frameImage: artwork, frame: frame)
        let assets = FrameRenderAssets(artwork: artwork, screenMask: mask)
        let geometry = CompositionGeometry(frame: frame, preset: .original)
        let prepared = CompositionRenderer.prepareFrame(assets: assets, geometry: geometry)
        let maskImage = try XCTUnwrap(CIContext().createCGImage(
            prepared.apertureMask,
            from: geometry.coreImageRect(fromTopLeft: geometry.screenRect)
        ))

        let localIslandCenterX = Int(island.midX - frame.screenRect.minX)
        let localIslandCenterY = Int(frame.screenRect.maxY - island.midY)
        XCTAssertGreaterThan(alpha(maskImage, x: localIslandCenterX, y: localIslandCenterY), 247)

        let content = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: frame.screenRect.size))
        let output = CompositionRenderer.composite(
            content: content,
            preparedFrame: prepared,
            geometry: geometry,
            background: .transparent
        )
        let outputImage = try XCTUnwrap(CIContext().createCGImage(
            output,
            from: CGRect(origin: .zero, size: geometry.outputSize)
        ))
        let islandPixel = rgbaAtTopLeft(outputImage, x: Int(island.midX), y: Int(island.midY))
        XCTAssertLessThan(islandPixel.red, 32)
        XCTAssertLessThan(islandPixel.green, 32)
        XCTAssertLessThan(islandPixel.blue, 32)
    }

    func testScreenMaskFillsNotchConnectedToTopBezel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appendingPathComponent("Notch Phone - Black - Portrait.png")
        let notch = CGRect(x: 140, y: 40, width: 80, height: 42)
        try TestImageFactory.writeFrame(
            to: frameURL,
            screenCornerRadius: 48,
            screenOcclusions: [notch]
        )
        let frame = try FrameScanner.scan(url: frameURL)
        let artwork = TestImageFactory.image(at: frameURL)
        let mask = try CompositionRenderer.makeScreenMask(frameImage: artwork, frame: frame)
        let assets = FrameRenderAssets(artwork: artwork, screenMask: mask)
        let image = try XCTUnwrap(CIContext().createCGImage(
            CIImage(cgImage: mask),
            from: CGRect(x: 0, y: 0, width: mask.width, height: mask.height)
        ))

        XCTAssertGreaterThan(
            alpha(image, x: Int(notch.midX - frame.screenRect.minX), y: mask.height - 20),
            247
        )

        let geometry = CompositionGeometry(frame: frame, preset: .original)
        let content = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: frame.screenRect.size))
        let output = CompositionRenderer.composite(
            content: content,
            preparedFrame: CompositionRenderer.prepareFrame(assets: assets, geometry: geometry),
            geometry: geometry,
            background: .transparent
        )
        let outputImage = try XCTUnwrap(CIContext().createCGImage(
            output,
            from: CGRect(origin: .zero, size: geometry.outputSize)
        ))
        let notchPixel = rgbaAtTopLeft(outputImage, x: Int(notch.midX), y: Int(notch.midY))
        XCTAssertLessThan(notchPixel.red, 32)
        XCTAssertLessThan(notchPixel.green, 32)
        XCTAssertLessThan(notchPixel.blue, 32)
    }

    func testPreviewSizeFitsViewportWithoutUpscaling() {
        XCTAssertEqual(
            ImageRenderer.previewPixelSize(
                outputSize: CGSize(width: 1_470, height: 3_000),
                maximumPixelSize: CGSize(width: 900, height: 1_200)
            ),
            CGSize(width: 588, height: 1_200)
        )
        XCTAssertEqual(
            ImageRenderer.previewPixelSize(
                outputSize: CGSize(width: 360, height: 720),
                maximumPixelSize: CGSize(width: 2_000, height: 2_000)
            ),
            CGSize(width: 360, height: 720)
        )
    }

    func testDisplayPreviewIsDownsampledWhileFullRenderKeepsOutputSize() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appendingPathComponent("Test Phone - Black - Portrait.png")
        let contentURL = directory.appendingPathComponent("capture.png")
        try TestImageFactory.writeFrame(to: frameURL, screenCornerRadius: 48)
        try TestImageFactory.writeCapture(to: contentURL)
        let frame = try FrameScanner.scan(url: frameURL)
        let artwork = TestImageFactory.image(at: frameURL)
        let assets = FrameRenderAssets(
            artwork: artwork,
            screenMask: try CompositionRenderer.makeScreenMask(frameImage: artwork, frame: frame)
        )
        let renderer = ImageRenderer()
        let settings = RenderSettings(frameID: frame.id)

        let preview = try renderer.preview(
            contentURL: contentURL,
            assets: assets,
            frame: frame,
            settings: settings,
            maximumPixelSize: CGSize(width: 180, height: 180)
        )
        let fullResolution = try renderer.render(
            contentURL: contentURL,
            assets: assets,
            frame: frame,
            settings: settings
        )

        XCTAssertEqual(CGSize(width: preview.width, height: preview.height), CGSize(width: 90, height: 180))
        XCTAssertEqual(CGSize(width: fullResolution.width, height: fullResolution.height), frame.canvasSize)
    }

    func testRoundedPNGOutputKeepsOuterCornersTransparent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appendingPathComponent("Rounded Phone - Black - Portrait.png")
        let contentURL = directory.appendingPathComponent("capture.png")
        let destinationURL = directory.appendingPathComponent("framed.png")
        try TestImageFactory.writeFrame(
            to: frameURL,
            screenCornerRadius: 48,
            deviceCornerRadius: 110
        )
        try TestImageFactory.writeCapture(to: contentURL)
        let frame = try FrameScanner.scan(url: frameURL)
        let renderer = ImageRenderer()
        let image = try renderer.render(
            contentURL: contentURL,
            frameURL: frameURL,
            frame: frame,
            settings: RenderSettings(frameID: frame.id)
        )

        try renderer.writePNG(image, to: destinationURL)

        let outputImage = TestImageFactory.image(at: destinationURL)
        XCTAssertLessThan(alpha(outputImage, x: 0, y: 0), 8)
        XCTAssertLessThan(alpha(outputImage, x: 20, y: 40), 8)
        XCTAssertGreaterThan(alpha(outputImage, x: 33, y: 53), 247)
        XCTAssertGreaterThan(alpha(outputImage, x: outputImage.width / 2, y: outputImage.height / 2), 247)
    }

    func testLocalIPhone17ProMaxFrameKeepsRoundedOuterCornersCleanWhenFixturesExist() throws {
        let libraryURL = URL(fileURLWithPath: "/Users/xuemingbo/Library/Containers/com.xuemingbo.SimFrame/Data/Library/Application Support/SimFrame/FrameLibrary")
        let frameURL = libraryURL.appendingPathComponent("Frames/iphone-17-pro-max-cosmic-orange-portrait.png")
        let manifestURL = libraryURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: frameURL.path),
              FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw XCTSkip("Local iPhone 17 Pro Max frame fixture is unavailable")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let contentURL = directory.appendingPathComponent("capture.png")
        let destinationURL = directory.appendingPathComponent("iphone-17-pro-max.png")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(FrameLibraryManifest.self, from: Data(contentsOf: manifestURL))
        let frame = try XCTUnwrap(manifest.frames.first {
            $0.id == "iphone-17-pro-max-cosmic-orange-portrait"
        })
        try TestImageFactory.writeCapture(to: contentURL, size: frame.screenRect.size)
        let renderer = ImageRenderer()
        let image = try renderer.render(
            contentURL: contentURL,
            frameURL: frameURL,
            frame: frame,
            settings: RenderSettings(frameID: frame.id)
        )

        try renderer.writePNG(image, to: destinationURL)

        let outputImage = TestImageFactory.image(at: destinationURL)
        let screenRect = frame.screenRect.integral
        XCTAssertLessThan(alpha(outputImage, x: 0, y: 0), 8)
        XCTAssertLessThan(alpha(outputImage, x: Int(screenRect.minX), y: Int(screenRect.minY)), 8)
        XCTAssertLessThan(alpha(outputImage, x: Int(screenRect.maxX) - 1, y: Int(screenRect.maxY) - 1), 8)
        XCTAssertGreaterThan(
            alpha(outputImage, x: Int(screenRect.midX), y: Int(screenRect.midY)),
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

    private func rgbaAtTopLeft(
        _ image: CGImage,
        x: Int,
        y: Int
    ) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let index = y * bytesPerRow + x * 4
        return (pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3])
    }
}
