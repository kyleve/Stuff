import UIKit

/// A single RGBA pixel sampled from a rendered snapshot, with components in
/// `0...1`. Shared by the pipeline regression tests that assert on rendered
/// colors rather than reference images.
///
/// `@_spi(Testing)`: a probe for snapshot-pipeline tests, not shipping API.
@_spi(Testing)
public struct PixelSample {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat
}

@_spi(Testing)
extension UIImage {
    /// Samples the pixel at a unit-space point (`(0.5, 0.5)` is the center),
    /// clamped to the image bounds. Returns transparent black if the image has
    /// no bitmap backing.
    public func probePixel(atUnitPoint unit: CGPoint) -> PixelSample {
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
