import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Regression guard for the tile-and-stitch capture path. UIKit renders a blank
/// image for views taller/wider than ~2000pt (verified reproducing on this
/// toolchain), so the pipeline captures oversized views in tiles. A short view
/// (single tile) and a very tall view (multiple tiles) must both come out whole.
@MainActor
struct LargeViewCaptureTests {
    @Test func capturesAShortViewInOneTile() throws {
        let sample = try renderTwoTone(height: 800)
        #expect(sample.size.height == 800)
        #expect(sample.top.red > 0.5)
        #expect(sample.bottom.blue > 0.5)
    }

    @Test func capturesAViewTallerThanTheTileLimit() throws {
        let sample = try renderTwoTone(height: 3000)
        #expect(sample.size.height == 3000)
        #expect(sample.top.red > 0.5)
        #expect(sample.bottom.blue > 0.5)
    }

    private func renderTwoTone(height: CGFloat) throws -> TwoToneSample {
        try waitFor { hostKeyWindow() != nil }
        let half = height / 2
        let view = VStack(spacing: 0) {
            Color.red.frame(height: half)
            Color.blue.frame(height: half)
        }
        .frame(width: 402, height: height)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: height)
        let image = renderSnapshotImage(of: host, safeAreaInsets: .zero)
        return TwoToneSample(
            top: image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.1)),
            bottom: image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.9)),
            size: image.size,
        )
    }
}

private struct TwoToneSample {
    let top: PixelSample
    let bottom: PixelSample
    let size: CGSize
}

private struct PixelSample {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
}

extension UIImage {
    fileprivate func probePixel(atUnitPoint unit: CGPoint) -> PixelSample {
        guard let cgImage else { return PixelSample(red: 0, green: 0, blue: 0, alpha: 0) }
        let x = min(cgImage.width - 1, max(0, Int(CGFloat(cgImage.width) * unit.x)))
        let y = min(cgImage.height - 1, max(0, Int(CGFloat(cgImage.height) * unit.y)))
        guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
            return PixelSample(red: 0, green: 0, blue: 0, alpha: 0)
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            return PixelSample(red: 0, green: 0, blue: 0, alpha: 0)
        }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return PixelSample(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: CGFloat(pixel[3]) / 255,
        )
    }
}
