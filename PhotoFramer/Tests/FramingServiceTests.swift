import CoreGraphics
import Testing

@testable import PhotoFramer

@Suite
struct FramingServiceTests {

    // MARK: - Helpers

    /// Create a solid-color test image of the given dimensions.
    private func makeTestImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    // MARK: - cropToFill

    @Test func cropToFillWiderImageProducesTargetAspectRatio() {
        let image = makeTestImage(width: 1000, height: 500) // 2:1
        let result = FramingService.cropToFill(image: image, targetAspectRatio: 1.0)

        #expect(result != nil)
        #expect(result!.width == result!.height)
    }

    @Test func cropToFillTallerImageProducesTargetAspectRatio() {
        let image = makeTestImage(width: 500, height: 1000) // 1:2
        let result = FramingService.cropToFill(image: image, targetAspectRatio: 1.0)

        #expect(result != nil)
        #expect(result!.width == result!.height)
    }

    @Test func cropToFillPreservesAspectRatio() {
        let image = makeTestImage(width: 1000, height: 800)
        let targetAR: CGFloat = 4.0 / 6.0
        let result = FramingService.cropToFill(image: image, targetAspectRatio: targetAR)!

        let resultAR = CGFloat(result.width) / CGFloat(result.height)
        #expect(abs(resultAR - targetAR) < 0.01)
    }

    @Test func cropToFillDoesNotEnlargeImage() {
        let image = makeTestImage(width: 800, height: 600)
        let result = FramingService.cropToFill(image: image, targetAspectRatio: 1.0)!

        #expect(result.width <= 800)
        #expect(result.height <= 600)
    }

    // MARK: - fitWithMat

    @Test func fitWithMatOutputMatchesRequestedSize() {
        let image = makeTestImage(width: 800, height: 600)
        let outputSize = CGSize(width: 1000, height: 1000)
        let matColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

        let result = FramingService.fitWithMat(
            image: image,
            targetAspectRatio: 1.0,
            matColor: matColor,
            outputSize: outputSize
        )

        #expect(result != nil)
        #expect(result!.width == 1000)
        #expect(result!.height == 1000)
    }

    @Test func fitWithMatPortraitCanvas() {
        let image = makeTestImage(width: 800, height: 600)
        let outputSize = CGSize(width: 500, height: 1000)
        let matColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        let result = FramingService.fitWithMat(
            image: image,
            targetAspectRatio: 0.5,
            matColor: matColor,
            outputSize: outputSize
        )

        #expect(result != nil)
        #expect(result!.width == 500)
        #expect(result!.height == 1000)
    }

    // MARK: - outputSize

    @Test func outputSizeLandscapeUsesWidthAsLongestEdge() {
        let size = FramingService.outputSize(for: 16.0 / 9.0, resolution: 3000)
        #expect(size.width == 3000)
        #expect(size.height < 3000)
    }

    @Test func outputSizePortraitUsesHeightAsLongestEdge() {
        let size = FramingService.outputSize(for: 9.0 / 16.0, resolution: 3000)
        #expect(size.height == 3000)
        #expect(size.width < 3000)
    }

    @Test func outputSizeSquare() {
        let size = FramingService.outputSize(for: 1.0, resolution: 2000)
        #expect(size.width == 2000)
        #expect(size.height == 2000)
    }

    // MARK: - frame (integration)

    @Test func frameCropToFillProducesImage() {
        let image = makeTestImage(width: 1000, height: 800)
        var config = FramingConfiguration.default
        config.mode = .cropToFill
        config.outputResolution = 500

        let result = FramingService.frame(image: image, configuration: config)
        #expect(result != nil)
    }

    @Test func frameFitWithMatProducesImage() {
        let image = makeTestImage(width: 1000, height: 800)
        var config = FramingConfiguration.default
        config.mode = .fitWithMat
        config.outputResolution = 500

        let result = FramingService.frame(image: image, configuration: config)
        #expect(result != nil)
    }
}
