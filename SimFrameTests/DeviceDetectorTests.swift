import Foundation
import XCTest
@testable import SimFrame

final class DeviceDetectorTests: XCTestCase {
    func testExactResolutionTieIsStableAndAmbiguous() {
        let first = frame(id: "iphone-17-black", device: "iPhone 17")
        let second = frame(id: "iphone-17-pro-black", device: "iPhone 17 Pro")
        let capture = CaptureDescriptor(
            url: URL(fileURLWithPath: "/tmp/Simulator Screen Shot.png"),
            kind: .image,
            pixelSize: CGSize(width: 1206, height: 2622),
            duration: 0,
            nominalFrameRate: 0,
            hasAudio: false
        )
        let result = DeviceDetector.detect(capture: capture, frames: [second, first], lastFrameID: nil)
        XCTAssertTrue(result.isAmbiguous)
        XCTAssertEqual(result.best?.frame.id, first.id)
        XCTAssertTrue(result.best?.reasons.contains("Exact pixel size") == true)
    }

    func testFilenameWinsSameSizeTie() {
        let standard = frame(id: "iphone-17-black", device: "iPhone 17")
        let pro = frame(id: "iphone-17-pro-black", device: "iPhone 17 Pro")
        let capture = CaptureDescriptor(
            url: URL(fileURLWithPath: "/tmp/iPhone 17 Pro recording.mov"),
            kind: .video,
            pixelSize: CGSize(width: 1206, height: 2622),
            duration: 1,
            nominalFrameRate: 60,
            hasAudio: false
        )
        let result = DeviceDetector.detect(capture: capture, frames: [standard, pro], lastFrameID: nil)
        XCTAssertFalse(result.isAmbiguous)
        XCTAssertEqual(result.best?.frame.id, pro.id)
    }

    private func frame(id: String, device: String) -> DeviceFrame {
        DeviceFrame(
            id: id,
            device: device,
            variant: "Black",
            orientation: .portrait,
            frameFile: "Frames/\(id).png",
            canvasSize: CGSize(width: 1350, height: 2760),
            screenRect: CGRect(x: 72, y: 69, width: 1206, height: 2622),
            normalizedScreenRect: CGRect(x: 72 / 1350, y: 69 / 2760, width: 1206 / 1350, height: 2622 / 2760),
            expectedCaptureSizes: [CGSize(width: 1206, height: 2622)]
        )
    }
}

