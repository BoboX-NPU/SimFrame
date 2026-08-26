import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class ImageRenderer: @unchecked Sendable {
    private let context: CIContext

    init(context: CIContext = CIContext(options: [.cacheIntermediates: true])) {
        self.context = context
    }

    func render(
        contentURL: URL,
        frameURL: URL,
        frame: DeviceFrame,
        settings: RenderSettings
    ) throws -> CGImage {
        guard let content = CIImage(contentsOf: contentURL, options: [.applyOrientationProperty: true]),
              let frameImage = CIImage(contentsOf: frameURL, options: [.applyOrientationProperty: true]) else {
            throw SimFrameError.unsupportedFile
        }
        let geometry = CompositionGeometry(frame: frame, preset: settings.canvasPreset)
        let preparedFrame = CompositionRenderer.prepareFrame(frameImage, geometry: geometry)
        let output = CompositionRenderer.composite(
            content: content,
            preparedFrame: preparedFrame,
            geometry: geometry,
            background: settings.background
        )
        let bounds = CGRect(origin: .zero, size: geometry.outputSize)
        guard let image = context.createCGImage(output, from: bounds) else {
            throw SimFrameError.exportFailed("Core Image did not produce an output image")
        }
        return image
    }

    func preview(
        contentURL: URL,
        frameURL: URL,
        frame: DeviceFrame,
        settings: RenderSettings
    ) throws -> NSImage {
        let image = try render(contentURL: contentURL, frameURL: frameURL, frame: frame, settings: settings)
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    func screenApertureMask(frameURL: URL, frame: DeviceFrame) throws -> NSImage {
        guard let frameImage = CIImage(contentsOf: frameURL, options: [.applyOrientationProperty: true]) else {
            throw SimFrameError.invalidFrame("Unable to decode the selected frame")
        }
        let geometry = CompositionGeometry(frame: frame, preset: .original)
        let preparedFrame = CompositionRenderer.prepareFrame(frameImage, geometry: geometry)
        let screenBounds = geometry.coreImageRect(fromTopLeft: geometry.screenRect)
        guard let mask = context.createCGImage(preparedFrame.apertureMask, from: screenBounds) else {
            throw SimFrameError.invalidFrame("Unable to create the screen aperture mask")
        }
        return NSImage(cgImage: mask, size: NSSize(width: mask.width, height: mask.height))
    }

    func writePNG(_ image: CGImage, to destination: URL) throws {
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SimFrame-\(UUID().uuidString).png"
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard let writer = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw SimFrameError.exportFailed("Unable to create the PNG destination") }
        CGImageDestinationAddImage(writer, image, [kCGImagePropertyHasAlpha: true] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else {
            throw SimFrameError.exportFailed("ImageIO could not finalize the PNG")
        }
        try commit(temporaryURL: temporaryURL, to: destination)
    }

    private func commit(temporaryURL: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        }
    }
}

enum CompositionRenderer {
    struct PreparedFrame {
        let artwork: CIImage
        let apertureMask: CIImage
    }

    static func prepareFrame(_ frame: CIImage, geometry: CompositionGeometry) -> PreparedFrame {
        let targetFrame = geometry.coreImageRect(fromTopLeft: geometry.frameRect)
        let normalizedFrame = normalize(frame)
        let frameScaleX = targetFrame.width / max(normalizedFrame.extent.width, 1)
        let frameScaleY = targetFrame.height / max(normalizedFrame.extent.height, 1)
        var placedFrame = normalizedFrame.transformed(by: CGAffineTransform(scaleX: frameScaleX, y: frameScaleY))
        placedFrame = placedFrame.transformed(by: CGAffineTransform(
            translationX: targetFrame.minX - placedFrame.extent.minX,
            y: targetFrame.minY - placedFrame.extent.minY
        ))

        let targetScreen = geometry.coreImageRect(fromTopLeft: geometry.screenRect)
        let apertureMask = placedFrame
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: -1),
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: targetScreen)
        return PreparedFrame(artwork: placedFrame, apertureMask: apertureMask)
    }

    static func composite(
        content: CIImage,
        frame: CIImage,
        geometry: CompositionGeometry,
        background: RenderBackground
    ) -> CIImage {
        composite(
            content: content,
            preparedFrame: prepareFrame(frame, geometry: geometry),
            geometry: geometry,
            background: background
        )
    }

    static func composite(
        content: CIImage,
        preparedFrame: PreparedFrame,
        geometry: CompositionGeometry,
        background: RenderBackground
    ) -> CIImage {
        let outputBounds = CGRect(origin: .zero, size: geometry.outputSize)
        let baseColor: CIColor
        switch background.mode {
        case .transparent:
            baseColor = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        case .solid:
            let color = background.color
            baseColor = CIColor(
                red: CGFloat(color.red),
                green: CGFloat(color.green),
                blue: CGFloat(color.blue),
                alpha: CGFloat(color.alpha)
            )
        }
        var result = CIImage(color: baseColor).cropped(to: outputBounds)

        let targetScreen = geometry.coreImageRect(fromTopLeft: geometry.screenRect)
        let normalizedContent = normalize(content)
        let scale = max(
            targetScreen.width / max(normalizedContent.extent.width, 1),
            targetScreen.height / max(normalizedContent.extent.height, 1)
        )
        var placedContent = normalizedContent.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        placedContent = placedContent.transformed(by: CGAffineTransform(
            translationX: targetScreen.midX - placedContent.extent.midX,
            y: targetScreen.midY - placedContent.extent.midY
        ))
        placedContent = placedContent.cropped(to: targetScreen)
        let transparentScreen = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: targetScreen)
        placedContent = placedContent
            .applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: transparentScreen,
                "inputMaskImage": preparedFrame.apertureMask
            ])
            .cropped(to: targetScreen)

        if geometry.shadowRadius > 0 {
            var shadow = preparedFrame.artwork.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.28)
            ])
            shadow = shadow
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: geometry.shadowRadius])
                .cropped(to: outputBounds)
                .transformed(by: CGAffineTransform(translationX: 0, y: -geometry.shadowOffset))
            result = shadow.composited(over: result).cropped(to: outputBounds)
        }

        result = placedContent.composited(over: result)
        result = preparedFrame.artwork.composited(over: result)
        return result.cropped(to: outputBounds)
    }

    static func normalize(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX,
            y: -image.extent.minY
        ))
    }
}
