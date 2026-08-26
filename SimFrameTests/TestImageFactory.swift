import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import SimFrame

enum TestImageFactory {
    static func writeFrame(
        to url: URL,
        canvas: CGSize = CGSize(width: 360, height: 720),
        screen: CGRect = CGRect(x: 20, y: 40, width: 320, height: 640)
    ) throws {
        let context = try bitmapContext(size: canvas)
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(origin: .zero, size: canvas))
        context.clear(screen)
        try write(context.makeImage()!, to: url)
    }

    static func writeCapture(
        to url: URL,
        size: CGSize = CGSize(width: 320, height: 640)
    ) throws {
        let context = try bitmapContext(size: size)
        context.setFillColor(CGColor(red: 0.1, green: 0.45, blue: 0.95, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
        try write(context.makeImage()!, to: url)
    }

    static func image(at url: URL) -> CGImage {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return CGImageSourceCreateImageAtIndex(source, 0, nil)!
    }

    private static func bitmapContext(size: CGSize) throws -> CGContext {
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SimFrameError.exportFailed("Test bitmap allocation failed") }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        return context
    }

    static func write(_ image: CGImage, to url: URL) throws {
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SimFrameError.exportFailed("Test PNG write failed")
        }
    }
}
