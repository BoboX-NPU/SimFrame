import AppKit
import CoreImage
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
        assets: FrameRenderAssets,
        frame: DeviceFrame,
        settings: RenderSettings
    ) throws -> CGImage {
        try renderedImage(
            contentURL: contentURL,
            assets: assets,
            frame: frame,
            settings: settings,
            maximumPixelSize: nil
        )
    }

    func preview(
        contentURL: URL,
        assets: FrameRenderAssets,
        frame: DeviceFrame,
        settings: RenderSettings,
        maximumPixelSize: CGSize
    ) throws -> CGImage {
        try renderedImage(
            contentURL: contentURL,
            assets: assets,
            frame: frame,
            settings: settings,
            maximumPixelSize: maximumPixelSize
        )
    }

    /// Retained for the developer inspector and focused renderer tests. Production
    /// paths obtain precomputed assets from `FrameLibraryService`.
    func render(
        contentURL: URL,
        frameURL: URL,
        frame: DeviceFrame,
        settings: RenderSettings
    ) throws -> CGImage {
        let assets = try Self.loadUncachedAssets(frameURL: frameURL, frame: frame)
        return try render(contentURL: contentURL, assets: assets, frame: frame, settings: settings)
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
        let assets = try Self.loadUncachedAssets(frameURL: frameURL, frame: frame)
        return NSImage(
            cgImage: assets.screenMask,
            size: NSSize(width: assets.screenMask.width, height: assets.screenMask.height)
        )
    }

    static func previewPixelSize(outputSize: CGSize, maximumPixelSize: CGSize) -> CGSize {
        guard outputSize.width > 0, outputSize.height > 0,
              maximumPixelSize.width > 0, maximumPixelSize.height > 0 else {
            return outputSize
        }
        let scale = min(
            maximumPixelSize.width / outputSize.width,
            maximumPixelSize.height / outputSize.height,
            1
        )
        return CGSize(
            width: max(1, (outputSize.width * scale).rounded()),
            height: max(1, (outputSize.height * scale).rounded())
        )
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

    private func renderedImage(
        contentURL: URL,
        assets: FrameRenderAssets,
        frame: DeviceFrame,
        settings: RenderSettings,
        maximumPixelSize: CGSize?
    ) throws -> CGImage {
        guard let content = CIImage(contentsOf: contentURL, options: [.applyOrientationProperty: true]) else {
            throw SimFrameError.unsupportedFile
        }
        let geometry = CompositionGeometry(frame: frame, preset: settings.canvasPreset)
        let preparedFrame = CompositionRenderer.prepareFrame(assets: assets, geometry: geometry)
        var output = CompositionRenderer.composite(
            content: content,
            preparedFrame: preparedFrame,
            geometry: geometry,
            background: settings.background
        )
        var bounds = CGRect(origin: .zero, size: geometry.outputSize)
        if let maximumPixelSize {
            let previewSize = Self.previewPixelSize(
                outputSize: geometry.outputSize,
                maximumPixelSize: maximumPixelSize
            )
            let scaleX = previewSize.width / geometry.outputSize.width
            let scaleY = previewSize.height / geometry.outputSize.height
            output = output.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            bounds = CGRect(origin: .zero, size: previewSize)
        }
        guard let image = context.createCGImage(output, from: bounds) else {
            throw SimFrameError.exportFailed("Core Image did not produce an output image")
        }
        return image
    }

    private static func loadUncachedAssets(frameURL: URL, frame: DeviceFrame) throws -> FrameRenderAssets {
        guard let source = CGImageSourceCreateWithURL(frameURL as CFURL, nil),
              let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SimFrameError.invalidFrame("Unable to decode the selected frame")
        }
        return FrameRenderAssets(
            artwork: artwork,
            screenMask: try CompositionRenderer.makeScreenMask(frameImage: artwork, frame: frame)
        )
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
    private static let apertureOverlapRadius = 2

    struct PreparedFrame {
        let artwork: CIImage
        let apertureMask: CIImage
    }

    static func prepareFrame(assets: FrameRenderAssets, geometry: CompositionGeometry) -> PreparedFrame {
        let targetFrame = geometry.coreImageRect(fromTopLeft: geometry.frameRect)
        let normalizedFrame = topLeftOrientedImage(assets.artwork)
        let frameScaleX = targetFrame.width / max(normalizedFrame.extent.width, 1)
        let frameScaleY = targetFrame.height / max(normalizedFrame.extent.height, 1)
        var placedFrame = normalizedFrame.transformed(by: CGAffineTransform(scaleX: frameScaleX, y: frameScaleY))
        placedFrame = placedFrame.transformed(by: CGAffineTransform(
            translationX: targetFrame.minX - placedFrame.extent.minX,
            y: targetFrame.minY - placedFrame.extent.minY
        ))

        let targetScreen = geometry.coreImageRect(fromTopLeft: geometry.screenRect)
        let normalizedMask = topLeftOrientedImage(assets.screenMask)
        let maskScaleX = targetScreen.width / max(normalizedMask.extent.width, 1)
        let maskScaleY = targetScreen.height / max(normalizedMask.extent.height, 1)
        var placedMask = normalizedMask.transformed(by: CGAffineTransform(scaleX: maskScaleX, y: maskScaleY))
        placedMask = placedMask.transformed(by: CGAffineTransform(
            translationX: targetScreen.minX - placedMask.extent.minX,
            y: targetScreen.minY - placedMask.extent.minY
        )).cropped(to: targetScreen)
        return PreparedFrame(artwork: placedFrame, apertureMask: placedMask)
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
        )).cropped(to: targetScreen)
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

    private static func topLeftOrientedImage(_ image: CGImage) -> CIImage {
        normalize(CIImage(cgImage: image))
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(image.height)))
    }

    static func makeScreenMask(frameImage: CGImage, frame: DeviceFrame) throws -> CGImage {
        try makeScreenMask(analysis: FrameScanner.analyze(image: frameImage), frame: frame)
    }

    static func makeScreenMask(
        analysis: FrameScanner.AlphaAnalysis,
        frame: DeviceFrame
    ) throws -> CGImage {
        let width = analysis.width
        let height = analysis.height
        guard width > 0, height > 0 else {
            throw SimFrameError.invalidFrame("Unable to inspect the selected frame aperture")
        }
        let exterior = connectedExteriorRegion(
            alpha: analysis.alpha,
            width: width,
            height: height,
            maximumAlpha: 247
        )
        var expanded = orthogonalSpanHull(
            aperture: analysis.aperture,
            width: width,
            height: height,
            screenRect: frame.screenRect.integral
        )
        dilate(
            &expanded,
            width: width,
            height: height,
            radius: apertureOverlapRadius
        )
        return try croppedGrayscaleMask(
            expanded: expanded,
            exterior: exterior,
            frameSize: CGSize(width: width, height: height),
            screenRect: frame.screenRect.integral
        )
    }

    private static func orthogonalSpanHull(
        aperture: [UInt8],
        width: Int,
        height: Int,
        screenRect: CGRect
    ) -> [UInt8] {
        let minX = max(0, Int(screenRect.minX))
        let maxX = min(width - 1, Int(screenRect.maxX) - 1)
        let minY = max(0, Int(screenRect.minY))
        let maxY = min(height - 1, Int(screenRect.maxY) - 1)
        var hull = aperture
        guard minX <= maxX, minY <= maxY else { return hull }
        aperture.withUnsafeBufferPointer { apertureBuffer in
            hull.withUnsafeMutableBufferPointer { hullBuffer in
                let aperturePixels = apertureBuffer.baseAddress!
                let hullPixels = hullBuffer.baseAddress!
                var y = minY
                while y <= maxY {
                    let row = y * width
                    var first = -1
                    var last = -1
                    var x = minX
                    while x <= maxX {
                        if aperturePixels[row + x] != 0 {
                            if first < 0 { first = x }
                            last = x
                        }
                        x += 1
                    }
                    if first >= 0 {
                        x = first
                        while x <= last {
                            hullPixels[row + x] = 1
                            x += 1
                        }
                    }
                    y += 1
                }
                var x = minX
                while x <= maxX {
                    var first = -1
                    var last = -1
                    y = minY
                    while y <= maxY {
                        if aperturePixels[y * width + x] != 0 {
                            if first < 0 { first = y }
                            last = y
                        }
                        y += 1
                    }
                    if first >= 0 {
                        y = first
                        while y <= last {
                            hullPixels[y * width + x] = 1
                            y += 1
                        }
                    }
                    x += 1
                }
            }
        }
        return hull
    }

    private static func dilate(_ flags: inout [UInt8], width: Int, height: Int, radius: Int) {
        guard radius > 0 else { return }
        var horizontal = [UInt8](repeating: 0, count: flags.count)
        flags.withUnsafeBufferPointer { flagBuffer in
            horizontal.withUnsafeMutableBufferPointer { horizontalBuffer in
                let source = flagBuffer.baseAddress!
                let destination = horizontalBuffer.baseAddress!
                var y = 0
                while y < height {
                    let row = y * width
                    var includedCount = 0
                    var x = 0
                    let initialEnd = min(width - 1, radius)
                    while x <= initialEnd {
                        if source[row + x] != 0 { includedCount += 1 }
                        x += 1
                    }
                    x = 0
                    while x < width {
                        destination[row + x] = includedCount > 0 ? 1 : 0
                        let outgoing = x - radius
                        if outgoing >= 0, source[row + outgoing] != 0 { includedCount -= 1 }
                        let incoming = x + radius + 1
                        if incoming < width, source[row + incoming] != 0 { includedCount += 1 }
                        x += 1
                    }
                    y += 1
                }
            }
        }
        horizontal.withUnsafeBufferPointer { horizontalBuffer in
            flags.withUnsafeMutableBufferPointer { flagBuffer in
                let source = horizontalBuffer.baseAddress!
                let destination = flagBuffer.baseAddress!
                var x = 0
                while x < width {
                    var includedCount = 0
                    var y = 0
                    let initialEnd = min(height - 1, radius)
                    while y <= initialEnd {
                        if source[y * width + x] != 0 { includedCount += 1 }
                        y += 1
                    }
                    y = 0
                    while y < height {
                        destination[y * width + x] = includedCount > 0 ? 1 : 0
                        let outgoing = y - radius
                        if outgoing >= 0, source[outgoing * width + x] != 0 { includedCount -= 1 }
                        let incoming = y + radius + 1
                        if incoming < height, source[incoming * width + x] != 0 { includedCount += 1 }
                        y += 1
                    }
                    x += 1
                }
            }
        }
    }

    private static func croppedGrayscaleMask(
        expanded: [UInt8],
        exterior: [UInt8],
        frameSize: CGSize,
        screenRect: CGRect
    ) throws -> CGImage {
        let frameWidth = Int(frameSize.width)
        let frameHeight = Int(frameSize.height)
        let minX = max(0, Int(screenRect.minX))
        let minY = max(0, Int(screenRect.minY))
        let maskWidth = min(frameWidth - minX, Int(screenRect.width))
        let maskHeight = min(frameHeight - minY, Int(screenRect.height))
        guard maskWidth > 0, maskHeight > 0 else {
            throw SimFrameError.invalidFrame("Unable to create the selected frame aperture mask")
        }
        let bytesPerRow = maskWidth * 2
        var data = Data(count: bytesPerRow * maskHeight)
        expanded.withUnsafeBufferPointer { expandedBuffer in
            exterior.withUnsafeBufferPointer { exteriorBuffer in
                data.withUnsafeMutableBytes { rawBuffer in
                    let expandedPixels = expandedBuffer.baseAddress!
                    let exteriorPixels = exteriorBuffer.baseAddress!
                    let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
                    var y = 0
                    while y < maskHeight {
                        var source = (minY + y) * frameWidth + minX
                        var destination = y * bytesPerRow
                        let sourceEnd = source + maskWidth
                        while source < sourceEnd {
                            if expandedPixels[source] != 0, exteriorPixels[source] == 0 {
                                bytes[destination] = 255
                                bytes[destination + 1] = 255
                            }
                            source += 1
                            destination += 2
                        }
                        y += 1
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                  width: maskWidth,
                  height: maskHeight,
                  bitsPerComponent: 8,
                  bitsPerPixel: 16,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw SimFrameError.invalidFrame("Unable to create the selected frame aperture mask")
        }
        return image
    }

    private static func connectedExteriorRegion(
        alpha: [UInt8],
        width: Int,
        height: Int,
        maximumAlpha: UInt8
    ) -> [UInt8] {
        var included = [UInt8](repeating: 0, count: width * height)
        let pixelCount = width * height
        let stack = UnsafeMutablePointer<Int32>.allocate(capacity: pixelCount)
        defer { stack.deallocate() }
        alpha.withUnsafeBufferPointer { alphaBuffer in
            included.withUnsafeMutableBufferPointer { includedBuffer in
                let alphaPixels = alphaBuffer.baseAddress!
                let includedPixels = includedBuffer.baseAddress!
                var stackCount = 0
                func addSeed(_ seed: Int) {
                    guard includedPixels[seed] == 0, alphaPixels[seed] <= maximumAlpha else { return }
                    includedPixels[seed] = 1
                    stack[stackCount] = Int32(seed)
                    stackCount += 1
                }
                var x = 0
                while x < width {
                    addSeed(x)
                    addSeed((height - 1) * width + x)
                    x += 1
                }
                var y = 1
                while y + 1 < height {
                    addSeed(y * width)
                    addSeed(y * width + width - 1)
                    y += 1
                }
                while stackCount > 0 {
                    stackCount -= 1
                    let index = Int(stack[stackCount])
                    let pixelX = index % width
                    let pixelY = index / width
                    if pixelX > 0 {
                        include(
                            index - 1,
                            alpha: alphaPixels,
                            maximumAlpha: maximumAlpha,
                            in: includedPixels,
                            stack: stack,
                            stackCount: &stackCount
                        )
                    }
                    if pixelX + 1 < width {
                        include(
                            index + 1,
                            alpha: alphaPixels,
                            maximumAlpha: maximumAlpha,
                            in: includedPixels,
                            stack: stack,
                            stackCount: &stackCount
                        )
                    }
                    if pixelY > 0 {
                        include(
                            index - width,
                            alpha: alphaPixels,
                            maximumAlpha: maximumAlpha,
                            in: includedPixels,
                            stack: stack,
                            stackCount: &stackCount
                        )
                    }
                    if pixelY + 1 < height {
                        include(
                            index + width,
                            alpha: alphaPixels,
                            maximumAlpha: maximumAlpha,
                            in: includedPixels,
                            stack: stack,
                            stackCount: &stackCount
                        )
                    }
                }
            }
        }
        return included
    }

    @inline(__always)
    private static func include(
        _ index: Int,
        alpha: UnsafePointer<UInt8>,
        maximumAlpha: UInt8,
        in included: UnsafeMutablePointer<UInt8>,
        stack: UnsafeMutablePointer<Int32>,
        stackCount: inout Int
    ) {
        guard included[index] == 0, alpha[index] <= maximumAlpha else { return }
        included[index] = 1
        stack[stackCount] = Int32(index)
        stackCount += 1
    }
}
