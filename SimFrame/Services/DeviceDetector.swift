import CoreGraphics
import Foundation

enum DeviceDetector {
    static func detect(
        capture: CaptureDescriptor,
        frames: [DeviceFrame],
        lastFrameID: String?
    ) -> DetectionResult {
        let filename = capture.url.deletingPathExtension().lastPathComponent.lowercased()
        let captureRatio = capture.pixelSize.width / max(capture.pixelSize.height, 1)
        let longestFilenameMatch = frames
            .map(\.device)
            .filter { filename.contains($0.lowercased()) }
            .map(\.count)
            .max()

        let candidates = frames
            .filter { $0.orientation == capture.orientation }
            .map { frame -> DetectionCandidate in
                var score = 0
                var reasons: [String] = []

                if frame.expectedCaptureSizes.contains(where: { Self.samePixels($0, capture.pixelSize) }) {
                    score += 100
                    reasons.append("Exact pixel size")
                }

                let expected = frame.expectedCaptureSizes.first ?? frame.screenRect.size
                let frameRatio = expected.width / max(expected.height, 1)
                let ratioDelta = abs(frameRatio - captureRatio) / max(frameRatio, 0.001)
                if ratioDelta < 0.001 {
                    score += 25
                    reasons.append("Exact aspect ratio")
                } else if ratioDelta < 0.015 {
                    score += 10
                    reasons.append("Close aspect ratio")
                }

                if filename.contains(frame.device.lowercased()), frame.device.count == longestFilenameMatch {
                    score += 35
                    reasons.append("Device name in filename")
                }
                if frame.id == lastFrameID {
                    score += 4
                    reasons.append("Last used device")
                }

                return DetectionCandidate(frame: frame, score: score, reasons: reasons)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.frame.id.localizedStandardCompare($1.frame.id) == .orderedAscending
            }

        let ambiguous: Bool
        if candidates.count > 1 {
            ambiguous = candidates[0].score == candidates[1].score
        } else {
            ambiguous = false
        }
        return DetectionResult(candidates: candidates, isAmbiguous: ambiguous)
    }

    static func needsCropping(captureSize: CGSize, frame: DeviceFrame) -> Bool {
        let captureRatio = captureSize.width / max(captureSize.height, 1)
        let frameRatio = frame.screenRect.width / max(frame.screenRect.height, 1)
        return abs(captureRatio - frameRatio) / max(frameRatio, 0.001) > 0.001
    }

    private static func samePixels(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        Int(lhs.width.rounded()) == Int(rhs.width.rounded()) &&
            Int(lhs.height.rounded()) == Int(rhs.height.rounded())
    }
}
