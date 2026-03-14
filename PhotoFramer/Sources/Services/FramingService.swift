import CoreGraphics
import SwiftUI

enum FramingService {

    /// Apply a full `FramingConfiguration` to an image.
    static func frame(image: CGImage, configuration: FramingConfiguration) -> CGImage? {
        let targetAR = configuration.frameSize.aspectRatio

        switch configuration.mode {
        case .cropToFill:
            guard let cropped = cropToFill(image: image, targetAspectRatio: targetAR) else {
                return nil
            }
            return cropped.scaled(maxDimension: configuration.outputResolution)

        case .fitWithMat:
            let outputSize = outputSize(
                for: targetAR,
                resolution: configuration.outputResolution
            )
            let cgColor = cgColor(from: configuration.matColor)
            return fitWithMat(
                image: image,
                targetAspectRatio: targetAR,
                matColor: cgColor,
                outputSize: outputSize
            )
        }
    }

    /// Crop the image to exactly fill the target aspect ratio, center-cropping the excess axis.
    static func cropToFill(image: CGImage, targetAspectRatio: CGFloat) -> CGImage? {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let imageAR = imageWidth / imageHeight

        let cropRect: CGRect
        if imageAR > targetAspectRatio {
            // Image is wider — crop horizontally
            let cropWidth = imageHeight * targetAspectRatio
            let originX = (imageWidth - cropWidth) / 2
            cropRect = CGRect(x: originX, y: 0, width: cropWidth, height: imageHeight)
        } else {
            // Image is taller — crop vertically
            let cropHeight = imageWidth / targetAspectRatio
            let originY = (imageHeight - cropHeight) / 2
            cropRect = CGRect(x: 0, y: originY, width: imageWidth, height: cropHeight)
        }

        return image.cropping(to: cropRect)
    }

    /// Fit the entire image inside the target aspect ratio with a colored mat around it.
    static func fitWithMat(
        image: CGImage,
        targetAspectRatio: CGFloat,
        matColor: CGColor,
        outputSize: CGSize
    ) -> CGImage? {
        let canvasWidth = outputSize.width
        let canvasHeight = outputSize.height
        let canvasAR = canvasWidth / canvasHeight

        let imageAR = CGFloat(image.width) / CGFloat(image.height)

        let drawRect: CGRect
        if imageAR > canvasAR {
            // Image is wider than canvas — fit to width
            let drawWidth = canvasWidth
            let drawHeight = drawWidth / imageAR
            let y = (canvasHeight - drawHeight) / 2
            drawRect = CGRect(x: 0, y: y, width: drawWidth, height: drawHeight)
        } else {
            // Image is taller than canvas — fit to height
            let drawHeight = canvasHeight
            let drawWidth = drawHeight * imageAR
            let x = (canvasWidth - drawWidth) / 2
            drawRect = CGRect(x: x, y: 0, width: drawWidth, height: drawHeight)
        }

        return image.drawnOnCanvas(
            canvasSize: outputSize,
            drawRect: drawRect,
            backgroundColor: matColor
        )
    }

    // MARK: - Helpers

    /// Calculate the output pixel dimensions for a target aspect ratio and resolution.
    static func outputSize(for aspectRatio: CGFloat, resolution: Int) -> CGSize {
        if aspectRatio >= 1 {
            // Landscape or square: width is the longest edge
            let width = CGFloat(resolution)
            let height = width / aspectRatio
            return CGSize(width: width, height: height)
        } else {
            // Portrait: height is the longest edge
            let height = CGFloat(resolution)
            let width = height * aspectRatio
            return CGSize(width: width, height: height)
        }
    }

    /// Convert a SwiftUI `Color` to a `CGColor`, falling back to white.
    private static func cgColor(from color: Color) -> CGColor {
        #if canImport(UIKit)
        UIColor(color).cgColor
        #else
        NSColor(color).cgColor
        #endif
    }
}
