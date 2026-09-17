import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes pixels into a fresh JPEG container without copying source metadata.
public struct JPEGExporter: Sendable {
    public init() {}
    public func stripMetadata(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw DaylightError.invalidImage }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            result,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ) else { throw DaylightError.invalidImage }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary,
        )
        guard CGImageDestinationFinalize(destination) else { throw DaylightError.invalidImage }
        return result as Data
    }
}
