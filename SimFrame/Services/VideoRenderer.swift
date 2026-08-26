@preconcurrency import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation

final class VideoRenderJob: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}

final class VideoRenderer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.xuemingbo.SimFrame.video-render", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func render(
        sourceURL: URL,
        destinationURL: URL,
        frameURL: URL,
        frame: DeviceFrame,
        settings: RenderSettings,
        job: VideoRenderJob,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.renderSynchronously(
                        sourceURL: sourceURL,
                        destinationURL: destinationURL,
                        frameURL: frameURL,
                        frame: frame,
                        settings: settings,
                        job: job,
                        progress: progress
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func renderSynchronously(
        sourceURL: URL,
        destinationURL: URL,
        frameURL: URL,
        frame: DeviceFrame,
        settings: RenderSettings,
        job: VideoRenderJob,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        if settings.exportFormat == .mp4 && settings.background.mode == .transparent {
            throw SimFrameError.mp4RequiresOpaqueBackground
        }
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw SimFrameError.missingVideoTrack
        }
        guard let frameImage = CIImage(contentsOf: frameURL, options: [.applyOrientationProperty: true]) else {
            throw SimFrameError.invalidFrame("Unable to decode the selected frame")
        }

        let geometry = CompositionGeometry(frame: frame, preset: settings.canvasPreset)
        let preparedFrame = CompositionRenderer.prepareFrame(frameImage, geometry: geometry)
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SimFrame-\(UUID().uuidString).\(settings.exportFormat.fileExtension)"
        )
        try? FileManager.default.removeItem(at: temporaryURL)
        var committed = false
        defer {
            if !committed { try? FileManager.default.removeItem(at: temporaryURL) }
        }

        let reader = try AVAssetReader(asset: asset)
        let naturalRect = CGRect(origin: .zero, size: videoTrack.naturalSize).applying(videoTrack.preferredTransform)
        let normalizedTrackTransform = videoTrack.preferredTransform.concatenating(
            CGAffineTransform(translationX: -naturalRect.minX, y: -naturalRect.minY)
        )
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(
            width: abs(naturalRect.width).rounded(),
            height: abs(naturalRect.height).rounded()
        )
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(max(1, Int32(videoTrack.nominalFrameRate.rounded())))
        )
        let compositionInstruction = AVMutableVideoCompositionInstruction()
        compositionInstruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(normalizedTrackTransform, at: .zero)
        compositionInstruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [compositionInstruction]

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw SimFrameError.exportFailed("Cannot read the source video") }
        reader.add(videoOutput)

        let fileType: AVFileType = settings.exportFormat == .mp4 ? .mp4 : .mov
        let writer = try AVAssetWriter(outputURL: temporaryURL, fileType: fileType)
        let codec: AVVideoCodecType
        if settings.exportFormat == .mp4 {
            codec = .h264
        } else if settings.background.mode == .transparent {
            codec = .hevcWithAlpha
        } else {
            codec = .hevc
        }
        let width = Int(geometry.outputSize.width)
        let height = Int(geometry.outputSize.height)
        let averageBitRate = Self.targetAverageBitRate(
            outputSize: geometry.outputSize,
            displayedSourceSize: videoComposition.renderSize,
            sourceEstimatedBitRate: Double(videoTrack.estimatedDataRate)
        )
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: averageBitRate,
                AVVideoExpectedSourceFrameRateKey: max(1, Int(videoTrack.nominalFrameRate.rounded()))
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw SimFrameError.exportFailed("The selected video codec is unavailable") }
        writer.add(videoInput)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output

                var sampleRate = 44_100.0
                var channelCount = 2
                if let rawDescription = audioTrack.formatDescriptions.first {
                    let description = rawDescription as! CMAudioFormatDescription
                    if let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description) {
                        sampleRate = stream.pointee.mSampleRate
                        channelCount = max(1, Int(stream.pointee.mChannelsPerFrame))
                    }
                }
                let input = AVAssetWriterInput(
                    mediaType: .audio,
                    outputSettings: [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVSampleRateKey: sampleRate,
                        AVNumberOfChannelsKey: channelCount,
                        AVEncoderBitRateKey: 192_000
                    ]
                )
                if writer.canAdd(input) {
                    writer.add(input)
                    audioInput = input
                }
            }
        }

        guard writer.startWriting() else {
            throw SimFrameError.exportFailed(writer.error?.localizedDescription ?? "Writer did not start")
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            throw SimFrameError.exportFailed(reader.error?.localizedDescription ?? "Reader did not start")
        }

        let durationSeconds = max(asset.duration.seconds, 0.001)
        var videoFinished = false
        var audioFinished = audioInput == nil
        var lastAdvance = Date()

        while !videoFinished || !audioFinished {
            if job.isCancelled {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: temporaryURL)
                throw CancellationError()
            }

            var advanced = false
            if !videoFinished, videoInput.isReadyForMoreMediaData {
                advanced = true
                if let sample = videoOutput.copyNextSampleBuffer(),
                   let sourceBuffer = CMSampleBufferGetImageBuffer(sample) {
                    guard let pool = adaptor.pixelBufferPool else {
                        throw SimFrameError.exportFailed("Video pixel buffer pool is unavailable")
                    }
                    var targetBuffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &targetBuffer) == kCVReturnSuccess,
                          let targetBuffer else {
                        throw SimFrameError.exportFailed("Unable to allocate a video frame")
                    }
                    let content = CompositionRenderer.normalize(CIImage(cvPixelBuffer: sourceBuffer))
                    let output = CompositionRenderer.composite(
                        content: content,
                        preparedFrame: preparedFrame,
                        geometry: geometry,
                        background: settings.background
                    )
                    ciContext.render(
                        output,
                        to: targetBuffer,
                        bounds: CGRect(origin: .zero, size: geometry.outputSize),
                        colorSpace: CGColorSpaceCreateDeviceRGB()
                    )
                    let time = CMSampleBufferGetPresentationTimeStamp(sample)
                    guard adaptor.append(targetBuffer, withPresentationTime: time) else {
                        throw SimFrameError.exportFailed(writer.error?.localizedDescription ?? "Unable to append a video frame")
                    }
                    progress(min(max(time.seconds / durationSeconds, 0), 0.99))
                } else {
                    videoInput.markAsFinished()
                    videoFinished = true
                }
            }

            if !audioFinished, let audioInput, let audioOutput, audioInput.isReadyForMoreMediaData {
                advanced = true
                if let sample = audioOutput.copyNextSampleBuffer() {
                    guard audioInput.append(sample) else {
                        throw SimFrameError.exportFailed(writer.error?.localizedDescription ?? "Unable to append audio")
                    }
                } else {
                    audioInput.markAsFinished()
                    audioFinished = true
                }
            }

            if !advanced { Thread.sleep(forTimeInterval: 0.002) }
            else { lastAdvance = Date() }

            if writer.status == .failed {
                throw SimFrameError.exportFailed(writer.error?.localizedDescription ?? "Video writer failed")
            }
            if reader.status == .failed {
                throw SimFrameError.exportFailed(reader.error?.localizedDescription ?? "Video reader failed")
            }
            if Date().timeIntervalSince(lastAdvance) > 30 {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: temporaryURL)
                throw SimFrameError.exportFailed("The video encoder stopped accepting frames")
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        if semaphore.wait(timeout: .now() + 30) == .timedOut {
            writer.cancelWriting()
            throw SimFrameError.exportFailed("The video encoder did not finish in time")
        }
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw SimFrameError.exportFailed(writer.error?.localizedDescription ?? "Writer did not finish")
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        }
        committed = true
        progress(1)
        AppLog.rendering.info("Video export completed")
    }

    static func targetAverageBitRate(
        outputSize: CGSize,
        displayedSourceSize: CGSize,
        sourceEstimatedBitRate: Double
    ) -> Int {
        let outputPixels = max(1, Double(outputSize.width * outputSize.height))
        let sourcePixels = max(1, Double(displayedSourceSize.width * displayedSourceSize.height))
        let qualityFloor = max(8_000_000, Int((outputPixels * 5).rounded(.up)))
        guard sourceEstimatedBitRate > 0 else { return qualityFloor }

        // Retain at least the source rate and scale it when the frame/background
        // increases the encoded pixel area. The small headroom offsets VBR drift.
        let areaScale = max(1, outputPixels / sourcePixels)
        let sourcePreservingRate = Int((sourceEstimatedBitRate * areaScale * 1.1).rounded(.up))
        return max(qualityFloor, sourcePreservingRate)
    }
}
