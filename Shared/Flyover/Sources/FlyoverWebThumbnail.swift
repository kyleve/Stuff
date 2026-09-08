#if DEBUG
    import CoreGraphics
    import Foundation
    import ImageIO

    /// Builds a card-sized PNG from one hosted full-resolution capture.
    struct FlyoverWebThumbnail {
        static let maximumPixelDimension = 1024

        let pngData: Data
        let pixelSize: CGSize

        @concurrent
        static func make(
            from pngData: Data,
            pointSize: CGSize,
            viewportPointSize: CGSize?,
        ) async throws -> Self {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
                  let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw FlyoverWebThumbnailError.invalidPNG
            }

            let croppedImage = try crop(
                sourceImage,
                pointSize: pointSize,
                viewportPointSize: viewportPointSize,
            )
            let longestDimension = max(croppedImage.width, croppedImage.height)
            let scale = min(
                1,
                CGFloat(maximumPixelDimension) / CGFloat(max(longestDimension, 1)),
            )
            let width = max(1, Int((CGFloat(croppedImage.width) * scale).rounded()))
            let height = max(1, Int((CGFloat(croppedImage.height) * scale).rounded()))

            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
                  )
            else {
                throw FlyoverWebThumbnailError.couldNotCreateBitmap
            }
            context.interpolationQuality = .high
            context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            try Task.checkCancellation()

            guard let thumbnailImage = context.makeImage() else {
                throw FlyoverWebThumbnailError.couldNotCreateBitmap
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output,
                "public.png" as CFString,
                1,
                nil,
            ) else {
                throw FlyoverWebThumbnailError.couldNotCreatePNG
            }
            CGImageDestinationAddImage(destination, thumbnailImage, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw FlyoverWebThumbnailError.couldNotCreatePNG
            }
            return FlyoverWebThumbnail(
                pngData: output as Data,
                pixelSize: CGSize(width: width, height: height),
            )
        }

        private static func crop(
            _ image: CGImage,
            pointSize: CGSize,
            viewportPointSize: CGSize?,
        ) throws -> CGImage {
            guard let viewportPointSize else {
                return image
            }
            guard pointSize.width > 0, pointSize.height > 0 else {
                throw FlyoverWebThumbnailError.invalidPointSize
            }
            let width = min(
                CGFloat(image.width),
                viewportPointSize.width * CGFloat(image.width) / pointSize.width,
            )
            let height = min(
                CGFloat(image.height),
                viewportPointSize.height * CGFloat(image.height) / pointSize.height,
            )
            guard width > 0, height > 0,
                  let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: width, height: height))
            else {
                throw FlyoverWebThumbnailError.couldNotCrop
            }
            return cropped
        }
    }

    enum FlyoverWebThumbnailError: Error, Equatable, LocalizedError {
        case invalidPNG
        case invalidPointSize
        case couldNotCrop
        case couldNotCreateBitmap
        case couldNotCreatePNG

        var errorDescription: String? {
            switch self {
                case .invalidPNG:
                    "The hosted capture is not a valid PNG."
                case .invalidPointSize:
                    "The hosted capture has an invalid point size."
                case .couldNotCrop:
                    "The capture viewport could not be cropped."
                case .couldNotCreateBitmap:
                    "The thumbnail bitmap could not be created."
                case .couldNotCreatePNG:
                    "The thumbnail PNG could not be encoded."
            }
        }
    }
#endif
