#if DEBUG
    import CoreGraphics
    import Foundation

    /// PNG bytes and dimensions returned by a hosted capture closure.
    public struct FlyoverCapturedImage: Sendable {
        public let pngData: Data
        public let pointSize: CGSize
        public let pixelSize: CGSize
        public let scale: CGFloat

        public init(
            pngData: Data,
            pointSize: CGSize,
            pixelSize: CGSize,
            scale: CGFloat,
        ) {
            self.pngData = pngData
            self.pointSize = pointSize
            self.pixelSize = pixelSize
            self.scale = scale
        }
    }
#endif
