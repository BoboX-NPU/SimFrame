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
        let preparedFrame = try CompositionRenderer.prepareFrame(frameImage, geometry: geometry)
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
        let preparedFrame = try CompositionRenderer.prepareFrame(frameImage, geometry: geometry)
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
    private static let apertureOverlapRadius: CGFloat = 2
    private static let maskContext = CIContext(options: [.cacheIntermediates: false])

    struct PreparedFrame {
        let artwork: CIImage
        let apertureMask: CIImage
    }

    static func prepareFrame(_ frame: CIImage, geometry: CompositionGeometry) throws -> PreparedFrame {
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
        let apertureMask = try isolatedApertureMask(from: placedFrame, in: targetScreen)
        return PreparedFrame(artwork: placedFrame, apertureMask: apertureMask)
    }

    static func composite(
        content: CIImage,
        frame: CIImage,
        geometry: CompositionGeometry,
        background: RenderBackground
    ) throws -> CIImage {
        try composite(
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

    private static func isolatedApertureMask(from frame: CIImage, in screenRect: CGRect) throws -> CIImage {
        let inspectionBounds = frame.extent.integral
        let width = Int(inspectionBounds.width.rounded())
        let height = Int(inspectionBounds.height.rounded())
        guard width > 0, height > 0,
              let frameImage = maskContext.createCGImage(frame, from: inspectionBounds) else {
            throw SimFrameError.invalidFrame("Unable to inspect the selected frame aperture")
        }

        let bytesPerRow = width * 4
        var framePixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let frameContext = CGContext(
            data: &framePixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SimFrameError.invalidFrame("Unable to inspect the selected frame aperture")
        }
        frameContext.draw(frameImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let alpha = (0..<(width * height)).map { framePixels[$0 * 4 + 3] }

        let localScreenCenter = CGPoint(
            x: screenRect.midX - inspectionBounds.minX,
            y: screenRect.midY - inspectionBounds.minY
        )
        guard let apertureSeed = nearestTransparentSeed(
            alpha: alpha,
            width: width,
            height: height,
            center: localScreenCenter
        ) else {
            throw SimFrameError.invalidFrame("Unable to isolate the selected frame aperture")
        }
        let aperture = connectedRegion(
            alpha: alpha,
            width: width,
            height: height,
            seeds: [apertureSeed],
            maximumAlpha: 8
        )
        let exterior = connectedRegion(
            alpha: alpha,
            width: width,
            height: height,
            seeds: borderPixels(width: width, height: height),
            maximumAlpha: 247
        )

        let apertureImage = try binaryMaskImage(flags: aperture, inverted: false, width: width, height: height)
        let safeInteriorImage = try binaryMaskImage(flags: exterior, inverted: true, width: width, height: height)
        let localBounds = CGRect(x: 0, y: 0, width: width, height: height)
        let expandedAperture = apertureImage
            .applyingFilter("CIMorphologyMaximum", parameters: [
                kCIInputRadiusKey: apertureOverlapRadius
            ])
            .cropped(to: localBounds)
        let transparent = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: localBounds)
        return expandedAperture
            .applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: transparent,
                "inputMaskImage": safeInteriorImage
            ])
            .cropped(to: localBounds)
            .transformed(by: CGAffineTransform(
                translationX: inspectionBounds.minX,
                y: inspectionBounds.minY
            ))
            .cropped(to: screenRect)
    }

    private static func binaryMaskImage(
        flags: [UInt8],
        inverted: Bool,
        width: Int,
        height: Int
    ) throws -> CIImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for index in flags.indices where (flags[index] == 0) == inverted {
            let pixel = index * 4
            pixels[pixel] = 255
            pixels[pixel + 1] = 255
            pixels[pixel + 2] = 255
            pixels[pixel + 3] = 255
        }
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw SimFrameError.invalidFrame("Unable to create the selected frame aperture mask")
        }
        return CIImage(cgImage: image)
    }

    private static func nearestTransparentSeed(
        alpha: [UInt8],
        width: Int,
        height: Int,
        center: CGPoint
    ) -> Int? {
        let centerX = min(max(Int(center.x.rounded()), 0), width - 1)
        let centerY = min(max(Int(center.y.rounded()), 0), height - 1)
        let maxRadius = min(width, height) / 4
        for radius in 0...maxRadius {
            let points = [
                (centerX + radius, centerY), (centerX - radius, centerY),
                (centerX, centerY + radius), (centerX, centerY - radius)
            ]
            for (x, y) in points where x >= 0 && x < width && y >= 0 && y < height {
                let index = y * width + x
                if alpha[index] <= 8 { return index }
            }
        }
        return nil
    }

    private static func borderPixels(width: Int, height: Int) -> [Int] {
        var pixels = [Int]()
        pixels.reserveCapacity((width + height) * 2)
        for x in 0..<width {
            pixels.append(x)
            pixels.append((height - 1) * width + x)
        }
        if height > 2 {
            for y in 1..<(height - 1) {
                pixels.append(y * width)
                pixels.append(y * width + width - 1)
            }
        }
        return pixels
    }

    private static func connectedRegion(
        alpha: [UInt8],
        width: Int,
        height: Int,
        seeds: [Int],
        maximumAlpha: UInt8
    ) -> [UInt8] {
        var included = [UInt8](repeating: 0, count: width * height)
        var queue = [Int]()
        queue.reserveCapacity(width * height / 2)
        for seed in seeds where included[seed] == 0 && alpha[seed] <= maximumAlpha {
            included[seed] = 1
            queue.append(seed)
        }

        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            if x > 0 {
                let neighbor = index - 1
                if included[neighbor] == 0, alpha[neighbor] <= maximumAlpha {
                    included[neighbor] = 1
                    queue.append(neighbor)
                }
            }
            if x + 1 < width {
                let neighbor = index + 1
                if included[neighbor] == 0, alpha[neighbor] <= maximumAlpha {
                    included[neighbor] = 1
                    queue.append(neighbor)
                }
            }
            if y > 0 {
                let neighbor = index - width
                if included[neighbor] == 0, alpha[neighbor] <= maximumAlpha {
                    included[neighbor] = 1
                    queue.append(neighbor)
                }
            }
            if y + 1 < height {
                let neighbor = index + width
                if included[neighbor] == 0, alpha[neighbor] <= maximumAlpha {
                    included[neighbor] = 1
                    queue.append(neighbor)
                }
            }
        }
        return included
    }
}
