@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CaptureService {
    static func inspect(url: URL) async throws -> CaptureDescriptor {
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .image) == true {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
                throw SimFrameError.unsupportedFile
            }
            return CaptureDescriptor(
                url: url,
                kind: .image,
                pixelSize: CGSize(width: width.doubleValue, height: height.doubleValue),
                duration: 0,
                nominalFrameRate: 0,
                hasAudio: false
            )
        }
        if type?.conforms(to: .movie) == true || ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased()) {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw SimFrameError.missingVideoTrack
            }
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = CGRect(origin: .zero, size: naturalSize).applying(transform)
            let duration = try await asset.load(.duration)
            let frameRate = try await track.load(.nominalFrameRate)
            let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
            return CaptureDescriptor(
                url: url,
                kind: .video,
                pixelSize: CGSize(width: abs(transformed.width), height: abs(transformed.height)),
                duration: duration.seconds.isFinite ? duration.seconds : 0,
                nominalFrameRate: Double(frameRate),
                hasAudio: hasAudio
            )
        }
        throw SimFrameError.unsupportedFile
    }
}

