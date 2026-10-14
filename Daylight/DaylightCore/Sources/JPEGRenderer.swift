import CoreImage
import Foundation
import ImageIO

/// Applies source orientation and optional downsampling when encoding a JPEG derivative.
public struct JPEGRenderer: Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    public init() {}
    public func renderJPEG(_ data: Data, maximumDimension: Double?) throws -> Data {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true])
        else { throw DaylightError.invalidImage }
        return try renderJPEG(image, maximumDimension: maximumDimension)
    }

    public func renderJPEG(_ image: CIImage, maximumDimension: Double?) throws -> Data {
        var output = image
        if let maximumDimension {
            guard maximumDimension.isFinite,
                  maximumDimension > 0 else { throw DaylightError.invalidImage }
            let scale = min(1, maximumDimension / max(image.extent.width, image.extent.height))
            output = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.jpegRepresentation(
                  of: output,
                  colorSpace: colorSpace,
                  options: [
                      kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.92,
                  ],
              )
        else { throw DaylightError.invalidImage }
        return data
    }
}
