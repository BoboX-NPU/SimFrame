import CoreGraphics
import Foundation

struct CompositionGeometry: Equatable, Sendable {
    let outputSize: CGSize
    let frameRect: CGRect
    let screenRect: CGRect
    let shadowRadius: CGFloat
    let shadowOffset: CGFloat

    init(frame: DeviceFrame, preset: CanvasPreset) {
        let horizontalPadding = (frame.canvasSize.width * preset.paddingFraction).rounded()
        let verticalPadding = (frame.canvasSize.height * preset.paddingFraction).rounded()
        let width = Self.even(frame.canvasSize.width + horizontalPadding * 2)
        let height = Self.even(frame.canvasSize.height + verticalPadding * 2)
        let actualX = (width - frame.canvasSize.width) / 2
        let actualY = (height - frame.canvasSize.height) / 2

        outputSize = CGSize(width: width, height: height)
        frameRect = CGRect(origin: CGPoint(x: actualX, y: actualY), size: frame.canvasSize)
        screenRect = frame.screenRect.offsetBy(dx: actualX, dy: actualY)
        shadowRadius = preset.hasShadow ? max(frame.canvasSize.width, frame.canvasSize.height) * 0.014 : 0
        shadowOffset = preset.hasShadow ? frame.canvasSize.height * 0.012 : 0
    }

    func coreImageRect(fromTopLeft rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: outputSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func even(_ value: CGFloat) -> CGFloat {
        let rounded = Int(value.rounded())
        return CGFloat(rounded.isMultiple(of: 2) ? rounded : rounded + 1)
    }
}

