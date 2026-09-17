import CoreImage
@testable import DaylightCore
import ImageIO
import Testing

struct JPEGRendererTests {
    @Test func derivativeRespectsDimensionsWithoutUpscaling() throws {
        let pixels = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 80, height: 40))
        for limit in [40.0, 160.0] {
            let data = try JPEGRenderer().renderJPEG(pixels, maximumDimension: limit)
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == Int(min(limit, 80)))
            #expect(image.height == image.width / 2)
        }
        #expect(throws: DaylightError.self) { try JPEGRenderer().renderJPEG(
            pixels,
            maximumDimension: .nan,
        ) }
    }
}
