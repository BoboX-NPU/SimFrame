@preconcurrency import AVFoundation
import AppKit
import CoreMedia
import CoreVideo
import Foundation
import SwiftUI
import XCTest
@testable import SimFrame

final class VideoRendererTests: XCTestCase {
    @MainActor
    func testStableVideoPlayerCanBeHostedWithoutAVKitSwiftUIBridge() {
        let player = AVPlayer()
        let host = NSHostingView(rootView: StableVideoPlayer(player: player))
        host.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        host.layoutSubtreeIfNeeded()

        XCTAssertFalse(host.subviews.isEmpty)
    }

    func testPlaybackControlsUsePreviewWidthWithinMinimumAndMaximumBounds() {
        let previewWidth: CGFloat = 1_000
        let portraitScreenApertureWidth: CGFloat = 240
        let controlsWidth = VideoPreviewLayout.playbackControlsWidth(availableWidth: previewWidth)

        XCTAssertEqual(VideoPreviewLayout.playbackControlsWidth(availableWidth: 300), 400)
        XCTAssertEqual(controlsWidth, 952)
        XCTAssertGreaterThan(controlsWidth, portraitScreenApertureWidth)
        XCTAssertEqual(VideoPreviewLayout.playbackControlsWidth(availableWidth: 1_600), 1_000)
    }

    func testTargetBitRatePreservesSourceQualityAcrossLargerCanvas() {
        let sourceSize = CGSize(width: 1_206, height: 2_622)
        let outputSize = CGSize(width: 1_320, height: 2_868)
        let sourceRate = 20_000_000.0
        let targetRate = VideoRenderer.targetAverageBitRate(
            outputSize: outputSize,
            displayedSourceSize: sourceSize,
            sourceEstimatedBitRate: sourceRate
        )
        let areaScale = Double(
            (outputSize.width * outputSize.height) / (sourceSize.width * sourceSize.height)
        )

        XCTAssertGreaterThanOrEqual(targetRate, Int((sourceRate * areaScale * 1.1).rounded(.up)))
        XCTAssertGreaterThan(targetRate, Int(sourceRate))
    }

    func testTargetBitRateUsesQualityFloorWhenSourceRateIsUnavailable() {
        XCTAssertEqual(
            VideoRenderer.targetAverageBitRate(
                outputSize: CGSize(width: 360, height: 720),
                displayedSourceSize: CGSize(width: 320, height: 640),
                sourceEstimatedBitRate: 0
            ),
            8_000_000
        )
    }

    func testTargetBitRateNeverDropsBelowSourceRate() {
        let sourceRate = 24_000_000.0
        let targetRate = VideoRenderer.targetAverageBitRate(
            outputSize: CGSize(width: 1_000, height: 2_000),
            displayedSourceSize: CGSize(width: 1_206, height: 2_622),
            sourceEstimatedBitRate: sourceRate
        )

        XCTAssertGreaterThanOrEqual(targetRate, Int((sourceRate * 1.1).rounded(.up)))
    }

    func testMP4ExportKeepsDurationAndUsesH264() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appendingPathComponent("Test Phone - Black - Portrait.png")
        let sourceURL = directory.appendingPathComponent("source.mov")
        let destinationURL = directory.appendingPathComponent("framed.mp4")
        try TestImageFactory.writeFrame(to: frameURL)
        try await makeVideo(at: sourceURL)
        let frame = try FrameScanner.scan(url: frameURL)
        var settings = RenderSettings(frameID: frame.id)
        settings.exportFormat = .mp4
        settings.background = .dark

        try await VideoRenderer().render(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            frameURL: frameURL,
            frame: frame,
            settings: settings,
            job: VideoRenderJob(),
            progress: { _ in }
        )

        let asset = AVURLAsset(url: destinationURL)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let codec = try XCTUnwrap(descriptions.first).mediaSubType
        XCTAssertEqual(codec.rawValue, kCMVideoCodecType_H264)
        XCTAssertEqual(duration.seconds, 0.5, accuracy: 1.0 / 30.0)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 360, height: 720))
    }

    func testVideoExportPreservesTopAndBottomOrientation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appendingPathComponent("Test Phone - Black - Portrait.png")
        let sourceURL = directory.appendingPathComponent("source.mov")
        let captureURL = directory.appendingPathComponent("source-frame.png")
        let destinationURL = directory.appendingPathComponent("framed.mp4")
        try TestImageFactory.writeFrame(to: frameURL)
        try await makeRotatedVideo(at: sourceURL)
        try TestImageFactory.write(try await frameImage(from: sourceURL), to: captureURL)
        let frame = try FrameScanner.scan(url: frameURL)
        var settings = RenderSettings(frameID: frame.id)
        settings.exportFormat = .mp4
        settings.background = .dark
        let expectedImage = try ImageRenderer().render(
            contentURL: captureURL,
            frameURL: frameURL,
            frame: frame,
            settings: settings
        )

        try await VideoRenderer().render(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            frameURL: frameURL,
            frame: frame,
            settings: settings,
            job: VideoRenderJob(),
            progress: { _ in }
        )

        let outputImage = try await frameImage(from: destinationURL)
        let samplePoints = [
            CGPoint(x: 100, y: 200),
            CGPoint(x: 260, y: 200),
            CGPoint(x: 100, y: 520),
            CGPoint(x: 260, y: 520)
        ]
        for point in samplePoints {
            let expected = rgba(expectedImage, x: Int(point.x), y: Int(point.y))
            let actual = rgba(outputImage, x: Int(point.x), y: Int(point.y))
            XCTAssertEqual(Int(actual.red), Int(expected.red), accuracy: 20, "red at \(point)")
            XCTAssertEqual(Int(actual.green), Int(expected.green), accuracy: 20, "green at \(point)")
            XCTAssertEqual(Int(actual.blue), Int(expected.blue), accuracy: 20, "blue at \(point)")
        }
    }

    func testTransparentMOVKeepsRoundedOuterCornersClean() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appendingPathComponent("Rounded Phone - Black - Portrait.png")
        let sourceURL = directory.appendingPathComponent("source.mov")
        let destinationURL = directory.appendingPathComponent("framed-alpha.mov")
        try TestImageFactory.writeFrame(
            to: frameURL,
            canvas: CGSize(width: 180, height: 360),
            screen: CGRect(x: 10, y: 20, width: 160, height: 320),
            screenCornerRadius: 24,
            deviceCornerRadius: 64
        )
        try await makeVideo(
            at: sourceURL,
            encodedSize: CGSize(width: 160, height: 320),
            transform: .identity,
            frameCount: 3
        )
        let frame = try FrameScanner.scan(url: frameURL)
        var settings = RenderSettings(frameID: frame.id)
        settings.exportFormat = .mov
        settings.background = .transparent

        try await VideoRenderer().render(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            frameURL: frameURL,
            frame: frame,
            settings: settings,
            job: VideoRenderJob(),
            progress: { _ in }
        )

        let asset = AVURLAsset(url: destinationURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        XCTAssertEqual(try XCTUnwrap(descriptions.first).mediaSubType.rawValue, kCMVideoCodecType_HEVC)
        let outputImage = try await frameImage(from: destinationURL)
        XCTAssertLessThan(rgba(outputImage, x: 0, y: 0).alpha, 8)
        XCTAssertLessThan(rgba(outputImage, x: 10, y: 20).alpha, 8)
        XCTAssertGreaterThan(rgba(outputImage, x: outputImage.width / 2, y: outputImage.height / 2).alpha, 247)
    }

    func testLocalTransparentMOVPreservesAudioAndAlphaWhenFixturesExist() async throws {
        let frameURL = URL(fileURLWithPath: "/Users/xuemingbo/Downloads/PNG-iPhone-17/iPhone 17 Pro/iPhone 17 Pro - Deep Blue - Portrait.png")
        let sourceURL = URL(fileURLWithPath: "/Users/xuemingbo/Developer/SimFrame/LocalFixtures/iphone-17-pro-grid-short-with-audio.mov")
        guard FileManager.default.fileExists(atPath: frameURL.path),
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw XCTSkip("Local validation assets are not present")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destinationURL = directory.appendingPathComponent("framed-alpha.mov")
        let frame = try FrameScanner.scan(url: frameURL)
        var settings = RenderSettings(frameID: frame.id)
        settings.exportFormat = .mov
        settings.background = .transparent

        try await VideoRenderer().render(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            frameURL: frameURL,
            frame: frame,
            settings: settings,
            job: VideoRenderJob(),
            progress: { _ in }
        )

        let asset = AVURLAsset(url: destinationURL)
        let duration = try await asset.load(.duration)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(audioTracks.count, 1)
        XCTAssertEqual(duration.seconds, 0.2, accuracy: 1.0 / 30.0)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        let descriptions = try await videoTrack.load(.formatDescriptions)
        XCTAssertEqual(try XCTUnwrap(descriptions.first).mediaSubType.rawValue, kCMVideoCodecType_HEVC)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        var actualTime = CMTime.zero
        let image = try generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: &actualTime)
        XCTAssertLessThan(alphaAtTopLeft(image), 8)
    }

    private func makeVideo(at url: URL) async throws {
        try await makeVideo(
            at: url,
            encodedSize: CGSize(width: 320, height: 640),
            transform: .identity
        )
    }

    private func makeRotatedVideo(at url: URL) async throws {
        try await makeVideo(
            at: url,
            encodedSize: CGSize(width: 640, height: 320),
            transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 320, ty: 0)
        )
    }

    private func makeVideo(
        at url: URL,
        encodedSize: CGSize,
        transform: CGAffineTransform,
        frameCount: Int = 15
    ) async throws {
        let width = Int(encodedSize.width)
        let height = Int(encodedSize.height)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try XCTUnwrap(adaptor.pixelBufferPool)
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer), kCVReturnSuccess)
            let pixelBuffer = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                let width = CVPixelBufferGetWidth(pixelBuffer)
                for y in 0..<height {
                    let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
                    for x in 0..<width {
                        let pixel = row.advanced(by: x * 4)
                        let left = x < width / 2
                        let firstHalf = y < height / 2
                        let color: (blue: UInt8, green: UInt8, red: UInt8)
                        switch (left, firstHalf) {
                        case (true, true): color = (0, 0, 255)
                        case (false, true): color = (0, 255, 0)
                        case (true, false): color = (255, 0, 0)
                        case (false, false): color = (0, 255, 255)
                        }
                        pixel[0] = color.blue
                        pixel[1] = color.green
                        pixel[2] = color.red
                        pixel[3] = 255
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? SimFrameError.exportFailed("Test source writer failed")
        }
    }

    private func frameImage(from url: URL) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        return try await generator.image(at: CMTime(value: 1, timescale: 30)).image
    }

    private func rgba(_ image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
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

    private func alphaAtTopLeft(_ image: CGImage) -> UInt8 {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels[3]
    }
}
