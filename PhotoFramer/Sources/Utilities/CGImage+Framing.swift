import CoreGraphics

extension CGImage {

    /// Scale the image so the longest edge equals `maxDimension`, preserving aspect ratio.
    func scaled(maxDimension: Int) -> CGImage? {
        let widthRatio = CGFloat(maxDimension) / CGFloat(width)
        let heightRatio = CGFloat(maxDimension) / CGFloat(height)
        let scale = min(widthRatio, heightRatio)

        let newWidth = Int(CGFloat(width) * scale)
        let newHeight = Int(CGFloat(height) * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    /// Draw this image into `drawRect` on a canvas of `canvasSize` filled with `backgroundColor`.
    func drawnOnCanvas(
        canvasSize: CGSize,
        drawRect: CGRect,
        backgroundColor: CGColor
    ) -> CGImage? {
        let canvasWidth = Int(canvasSize.width)
        let canvasHeight = Int(canvasSize.height)

        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(backgroundColor)
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        context.interpolationQuality = .high
        context.draw(self, in: drawRect)
        return context.makeImage()
    }
}
