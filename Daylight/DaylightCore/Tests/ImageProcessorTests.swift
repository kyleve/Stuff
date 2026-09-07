import CoreImage
@testable import DaylightCore
import Foundation
import ImageIO
import Testing

struct ImageProcessorTests {
    @Test func presetsRenderAndNeutralPreservesDimensions() throws {
        let processor = ImageProcessor()
        let image = CIImage(color: CIColor(red: 0.8, green: 0.3, blue: 0.15)).cropped(to: CGRect(
            x: 0,
            y: 0,
            width: 80,
            height: 40,
        ))
        let original = try processor.renderJPEG(image, recipe: .original, maximumDimension: nil)
        for preset in ImageRecipe.Preset.allCases {
            var recipe = ImageRecipe.original
            recipe.preset = preset
            let result = try processor.renderJPEG(original, recipe: recipe, maximumDimension: nil)
            let source = try #require(CGImageSourceCreateWithData(result as CFData, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(decoded.width == 80)
            #expect(decoded.height == 40)
            if preset == .monochrome {
                let filter = try CIFilter(
                    name: "CIAreaAverage",
                    parameters: [kCIInputImageKey: #require(CIImage(data: result))],
                )
                let average = try #require(filter?.outputImage)
                var bytes = [UInt8](repeating: 0, count: 4)
                CIContext().render(
                    average,
                    toBitmap: &bytes,
                    rowBytes: 4,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8,
                    colorSpace: CGColorSpaceCreateDeviceRGB(),
                )
                #expect(abs(Int(bytes[0]) - Int(bytes[1])) < 3)
            }
        }
    }

    @Test func rejectsInvalidDataAndRecipes() {
        #expect(throws: DaylightError.self) { try ImageProcessor().renderJPEG(
            Data(),
            recipe: .original,
            maximumDimension: nil,
        ) }
        var recipe = ImageRecipe.original
        recipe.exposure = .nan
        #expect(throws: DaylightError.self) { try recipe.validate() }
    }
}
