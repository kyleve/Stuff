import Testing
import UIKit

/// Exact channel values for settle-policy tests, independent of UIKit timing.
func settleTestImage(
    _ pixels: [UInt8],
    width: Int = 1,
    height: Int = 1,
    rowPadding: Int = 0,
    bitmapInfo: CGBitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
) throws -> CGImage {
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    return try #require(CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4 + rowPadding,
        space: space,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent,
    ))
}

/// Supplies a new render on each real settle pass without a racing timer.
@MainActor
final class ScriptedSettleView: UIView {
    private let drawSample: (CGContext, CGRect, Int) -> Void
    private(set) var sampleCount = 0

    init(drawSample: @escaping (CGContext, CGRect, Int) -> Void) {
        self.drawSample = drawSample
        super.init(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func drawHierarchy(in rect: CGRect, afterScreenUpdates _: Bool) -> Bool {
        guard let context = UIGraphicsGetCurrentContext() else {
            Issue.record("the settle sample must supply a drawing context")
            return false
        }
        sampleCount += 1
        drawSample(context, rect, sampleCount)
        return true
    }
}
