import CoreImage
@testable import DaylightCore
import ImageIO
import Testing
import UniformTypeIdentifiers

struct JPEGExporterTests {
    @Test func exportRemovesLocationAndCameraMetadataAfterOrientationIsApplied() throws {
        let pixels = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 80, height: 40))
        let cgImage = try #require(CIContext().createCGImage(pixels, from: pixels.extent))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ))
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.78,
                kCGImagePropertyGPSLatitudeRef: "N",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Private camera"],
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let rendered = try JPEGRenderer().renderJPEG(
            data as Data,
            maximumDimension: nil,
        )
        let clean = try JPEGExporter().stripMetadata(rendered)
        let source = try #require(CGImageSourceCreateWithData(clean as CFData, nil))
        let properties =
            try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        #expect(properties[kCGImagePropertyGPSDictionary as String] == nil)
        #expect(properties[kCGImagePropertyTIFFDictionary as String] == nil)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 40)
        #expect(image.height == 80)
    }
}
