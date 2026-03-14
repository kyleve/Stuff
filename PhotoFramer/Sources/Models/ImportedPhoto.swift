import CoreGraphics

struct ImportedPhoto {
    let cgImage: CGImage
    let originalWidth: Int
    let originalHeight: Int

    var aspectRatio: CGFloat {
        CGFloat(originalWidth) / CGFloat(originalHeight)
    }

    init(cgImage: CGImage) {
        self.cgImage = cgImage
        self.originalWidth = cgImage.width
        self.originalHeight = cgImage.height
    }
}
