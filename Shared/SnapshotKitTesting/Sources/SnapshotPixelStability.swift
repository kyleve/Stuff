import CoreGraphics
import Foundation

/// Proves a quiet window against one fixed sample, allowing bounded render noise.
/// Every normalized RGBA channel must remain within one 8-bit unit of the anchor.
@_spi(Testing) public struct SnapshotPixelStability {
    private struct Anchor {
        let sample: Sample
        let time: Duration
    }

    /// The existing quiet window, sampled at the settle loop's 16 ms cadence.
    static let quietDuration: Duration = .milliseconds(120)
    private var anchor: Anchor?
    private var matchingPasses = 0
    public private(set) var observedChange = false

    public init() {}

    /// Returns true after two matches span the quiet window. Missing samples
    /// break the proof. The caller separately enforces its floor and deadlines.
    public mutating func observe(_ image: CGImage?, at elapsed: Duration) -> Bool {
        let sample = image.flatMap(Sample.init)
        if let anchor, let sample, sample.matches(anchor.sample) {
            matchingPasses += 1
            return matchingPasses >= 2 && elapsed - anchor.time >= Self.quietDuration
        }

        // Never advance the anchor for tolerated noise: adjacent one-unit
        // matches could otherwise hide a slow fade across the quiet window.
        if anchor != nil { observedChange = true }
        anchor = sample.map { Anchor(sample: $0, time: elapsed) }
        matchingPasses = 0
        return false
    }

    /// The final comparison also normalizes to 8-bit, premultiplied sRGB RGBA.
    /// A packed buffer excludes source padding and fixes the channel layout.
    private struct Sample {
        /// Maximum absolute channel difference, in 8-bit units. There is no
        /// area allowance: one channel exceeding this limit resets the window.
        private static let maximumChannelDelta = 1
        let width: Int
        let height: Int
        let pixels: Data

        init?(_ image: CGImage) {
            let width = image.width
            let height = image.height
            guard width > 0, height > 0,
                  let space = CGColorSpace(name: CGColorSpace.sRGB)
            else { return nil }
            var pixels = Data(count: width * height * 4)
            let rendered = pixels.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard rendered else { return nil }
            self.width = width
            self.height = height
            self.pixels = pixels
        }

        func matches(_ other: Sample) -> Bool {
            guard width == other.width, height == other.height else { return false }
            if pixels == other.pixels { return true }
            return pixels.withUnsafeBytes { leftBytes in
                other.pixels.withUnsafeBytes { rightBytes in
                    let left = leftBytes.bindMemory(to: UInt8.self)
                    let right = rightBytes.bindMemory(to: UInt8.self)
                    for index in left.indices {
                        if abs(Int(left[index]) - Int(right[index])) > Self.maximumChannelDelta {
                            return false
                        }
                    }
                    return true
                }
            }
        }
    }
}
