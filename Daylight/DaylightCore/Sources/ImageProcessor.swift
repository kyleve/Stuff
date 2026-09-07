import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO

/// The same deterministic Core Image graph renders preview frames and full-size photographs.
public struct ImageProcessor: ImageProcessing {
    private let context = CIContext(options: [.cacheIntermediates: false])

    public init() {}
    public func render(_ original: Data, recipe: ImageRecipe) async throws -> Data {
        try renderJPEG(original, recipe: recipe, maximumDimension: nil)
    }

    public func renderJPEG(
        _ data: Data,
        recipe: ImageRecipe,
        maximumDimension: Double?,
    ) throws -> Data {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true])
        else { throw DaylightError.invalidImage }
        return try renderJPEG(image, recipe: recipe, maximumDimension: maximumDimension)
    }

    public func renderJPEG(
        _ image: CIImage,
        recipe: ImageRecipe,
        maximumDimension: Double?,
    ) throws -> Data {
        try recipe.validate()
        var output = image
        if let maximumDimension {
            let scale = min(1, maximumDimension / max(image.extent.width, image.extent.height))
            output = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let base = output
        switch recipe.preset {
            case .original: break
            case .warm:
                let filter = CIFilter.temperatureAndTint()
                filter.inputImage = output
                filter.neutral = CIVector(x: 6500, y: 0)
                filter.targetNeutral = CIVector(x: 5400, y: 0)
                output = try require(filter.outputImage)
            case .vivid:
                let filter = CIFilter.colorControls()
                filter.inputImage = output; filter.saturation = 1.25; filter.contrast = 1.12
                output = try require(filter.outputImage)
            case .monochrome:
                let filter = CIFilter.colorControls()
                filter.inputImage = output; filter.saturation = 0
                output = try require(filter.outputImage)
        }
        if recipe.preset != .original {
            let blend = CIFilter.dissolveTransition()
            blend.inputImage = base; blend.targetImage = output; blend.time = Float(recipe.strength)
            output = try require(blend.outputImage)
        }
        if recipe.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = output; filter.ev = Float(recipe.exposure)
            output = try require(filter.outputImage)
        }
        if recipe.contrast != 1 || recipe.saturation != 1 {
            let filter = CIFilter.colorControls()
            filter.inputImage = output; filter.contrast = Float(recipe.contrast); filter
                .saturation = Float(recipe.saturation)
            output = try require(filter.outputImage)
        }
        if recipe.highlights != 1 || recipe.shadows != 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output; filter.highlightAmount = Float(recipe.highlights); filter
                .shadowAmount = Float(recipe.shadows)
            output = try require(filter.outputImage)
        }
        if recipe.warmth != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = output; filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 6500 - recipe.warmth * 2000, y: 0)
            output = try require(filter.outputImage)
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.jpegRepresentation(
                  of: output.cropped(to: base.extent),
                  colorSpace: colorSpace,
                  options: [
                      kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.92,
                  ],
              )
        else { throw DaylightError.invalidImage }
        return data
    }

    private func require(_ image: CIImage?) throws -> CIImage {
        guard let image else { throw DaylightError.invalidImage }
        return image
    }
}
