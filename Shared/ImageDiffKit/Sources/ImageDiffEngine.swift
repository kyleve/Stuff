import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pixel dimensions after an image has been decoded and normalized.
public struct ImageDimensions: Hashable, Codable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "Image dimensions must be positive")
        self.width = width
        self.height = height
    }

    public var pixelCount: Int {
        width * height
    }
}

/// Controls exact pixel comparison and optional local heatmap generation.
public struct ImageDiffOptions: Hashable, Sendable {
    /// Per-channel deltas at or below this value are treated as equal.
    public let channelTolerance: UInt8
    public let generatesHeatmap: Bool

    public init(channelTolerance: UInt8, generatesHeatmap: Bool) {
        self.channelTolerance = channelTolerance
        self.generatesHeatmap = generatesHeatmap
    }

    public static let exact = ImageDiffOptions(channelTolerance: 0, generatesHeatmap: false)
    public static let exactWithHeatmap = ImageDiffOptions(
        channelTolerance: 0,
        generatesHeatmap: true,
    )
}

/// Actionable measurements for two same-sized normalized images.
public struct ImageDiffMetrics: Equatable, Sendable {
    public let dimensions: ImageDimensions
    public let changedPixels: Int
    public let maximumChannelDelta: UInt8
    /// The smallest top-left-origin pixel rectangle containing every change.
    public let changedBounds: CGRect?

    public init(
        dimensions: ImageDimensions,
        changedPixels: Int,
        maximumChannelDelta: UInt8,
        changedBounds: CGRect?,
    ) {
        self.dimensions = dimensions
        self.changedPixels = changedPixels
        self.maximumChannelDelta = maximumChannelDelta
        self.changedBounds = changedBounds
    }

    public var changedFraction: Double {
        guard dimensions.pixelCount > 0 else { return 0 }
        return Double(changedPixels) / Double(dimensions.pixelCount)
    }
}

/// A comparison is either measurable or honestly reports incompatible geometry.
public enum ImageDiffResult: Equatable, Sendable {
    case comparable(metrics: ImageDiffMetrics, heatmapPNGData: Data?)
    case dimensionMismatch(base: ImageDimensions, head: ImageDimensions)
}

public enum ImageDiffSide: String, Equatable, Sendable {
    case base
    case head
}

public enum ImageDiffError: LocalizedError, Equatable, Sendable {
    case undecodable(ImageDiffSide)
    case pixelNormalizationFailed(ImageDiffSide)
    case heatmapEncodingFailed

    public var errorDescription: String? {
        switch self {
            case let .undecodable(side):
                "The \(side.rawValue) image could not be decoded."
            case let .pixelNormalizationFailed(side):
                "The \(side.rawValue) image pixels could not be normalized."
            case .heatmapEncodingFailed:
                "The local heatmap could not be encoded as PNG."
        }
    }
}

/// Normalizes image data to 8-bit premultiplied RGBA and compares it locally.
public struct ImageDiffEngine: Sendable {
    public init() {}

    public func compare(
        base baseData: Data,
        head headData: Data,
        options: ImageDiffOptions,
    ) throws -> ImageDiffResult {
        let baseImage = try decode(baseData, side: .base)
        let headImage = try decode(headData, side: .head)
        let baseDimensions = ImageDimensions(width: baseImage.width, height: baseImage.height)
        let headDimensions = ImageDimensions(width: headImage.width, height: headImage.height)
        guard baseDimensions == headDimensions else {
            return .dimensionMismatch(base: baseDimensions, head: headDimensions)
        }

        let basePixels = try normalizedPixels(baseImage, side: .base)
        let headPixels = try normalizedPixels(headImage, side: .head)
        let comparison = comparePixels(
            basePixels,
            headPixels,
            dimensions: baseDimensions,
            tolerance: options.channelTolerance,
            generatesHeatmap: options.generatesHeatmap,
        )
        let heatmap = try comparison.heatmapPixels.map {
            try encodePNG(pixels: $0, dimensions: baseDimensions)
        }
        return .comparable(metrics: comparison.metrics, heatmapPNGData: heatmap)
    }

    private func decode(_ data: Data, side: ImageDiffSide) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ImageDiffError.undecodable(side)
        }
        return image
    }

    private func normalizedPixels(_ image: CGImage, side: ImageDiffSide) throws -> [UInt8] {
        let bytesPerPixel = 4
        var pixels = [UInt8](
            repeating: 0,
            count: image.width * image.height * bytesPerPixel,
        )
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            throw ImageDiffError.pixelNormalizationFailed(side)
        }
        context.setBlendMode(.copy)
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height),
        )
        return pixels
    }

    private func comparePixels(
        _ base: [UInt8],
        _ head: [UInt8],
        dimensions: ImageDimensions,
        tolerance: UInt8,
        generatesHeatmap: Bool,
    ) -> PixelComparison {
        var changedPixels = 0
        var maximumChannelDelta: UInt8 = 0
        var minimumX = dimensions.width
        var minimumY = dimensions.height
        var maximumX = -1
        var maximumY = -1
        var heatmap = generatesHeatmap
            ? [UInt8](repeating: 0, count: dimensions.pixelCount * 4)
            : nil

        for y in 0 ..< dimensions.height {
            let row = y * dimensions.width * 4
            for x in 0 ..< dimensions.width {
                let index = row + x * 4
                var pixelDelta: UInt8 = 0
                for channel in 0 ..< 4 {
                    let delta = UInt8(abs(Int(base[index + channel]) - Int(head[index + channel])))
                    pixelDelta = max(pixelDelta, delta)
                }
                maximumChannelDelta = max(maximumChannelDelta, pixelDelta)
                guard pixelDelta > tolerance else { continue }

                changedPixels += 1
                minimumX = min(minimumX, x)
                maximumX = max(maximumX, x)
                minimumY = min(minimumY, y)
                maximumY = max(maximumY, y)
                if heatmap != nil {
                    let alpha = max(pixelDelta, 96)
                    heatmap?[index] = alpha
                    heatmap?[index + 1] = UInt8(Int(alpha) * 32 / 255)
                    heatmap?[index + 2] = UInt8(Int(alpha) * 96 / 255)
                    heatmap?[index + 3] = alpha
                }
            }
        }

        let bounds = maximumX < 0
            ? nil
            : CGRect(
                x: minimumX,
                y: minimumY,
                width: maximumX - minimumX + 1,
                height: maximumY - minimumY + 1,
            )
        return PixelComparison(
            metrics: ImageDiffMetrics(
                dimensions: dimensions,
                changedPixels: changedPixels,
                maximumChannelDelta: maximumChannelDelta,
                changedBounds: bounds,
            ),
            heatmapPixels: heatmap,
        )
    }

    private func encodePNG(pixels: [UInt8], dimensions: ImageDimensions) throws -> Data {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                  width: dimensions.width,
                  height: dimensions.height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: dimensions.width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent,
              )
        else {
            throw ImageDiffError.heatmapEncodingFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil,
        ) else {
            throw ImageDiffError.heatmapEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageDiffError.heatmapEncodingFailed
        }
        return output as Data
    }
}

private struct PixelComparison {
    let metrics: ImageDiffMetrics
    let heatmapPixels: [UInt8]?
}
