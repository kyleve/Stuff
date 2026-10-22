import Foundation
import ImageIO
import SnapshotReviewCore

protocol ReviewImageLoading: Sendable {
    func image(_ snapshot: SnapshotImage, thumbnail: Bool) async throws -> CGImage
}

/// Bounded thumbnail cache. Full-resolution images belong only to the visible canvas.
actor ReviewImageLoader: ReviewImageLoading {
    struct Key: Hashable { var url: URL; var fingerprint: String }
    private struct Cached { var image: CGImage; var cost: Int }
    private var thumbnails: [Key: Cached] = [:]
    private var order: [Key] = []
    private let capacity = 64 * 1024 * 1024

    func image(_ snapshot: SnapshotImage, thumbnail: Bool) throws -> CGImage {
        let content = try snapshot.content.get()
        let key = Key(url: snapshot.url, fingerprint: content.fingerprint)
        if thumbnail, let cached = thumbnails[key] { return cached.image }
        try Task.checkCancellation()
        let bytes = try Data(contentsOf: snapshot.url, options: .mappedIfSafe)
        guard ReviewFileStore.fingerprint(bytes) == content.fingerprint
        else { throw ReviewError.imageChanged }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil)
        else { throw ReviewError.unavailableImage("The PNG cannot be decoded.") }
        let image: CGImage?
        if thumbnail {
            image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 720,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary,
            )
        } else {
            guard content.pixels.width <= 32000, content.pixels.height <= 32000,
                  Int64(content.pixels.width) * Int64(content.pixels.height) <= 100_000_000
            else {
                throw ReviewError
                    .unavailableImage(
                        "This image exceeds the canvas limit of 32,000 pixels per dimension or 100 million pixels.",
                    )
            }
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { throw ReviewError.unavailableImage("The PNG cannot be decoded.") }
        try Task.checkCancellation()
        if thumbnail {
            thumbnails[key] = Cached(image: image, cost: image.bytesPerRow * image.height)
            order.append(key)
            while thumbnails.values.reduce(0, { $0 + $1.cost }) > capacity,
                  let oldest = order.first
            {
                order.removeFirst()
                thumbnails.removeValue(forKey: oldest)
            }
        }
        return image
    }
}
