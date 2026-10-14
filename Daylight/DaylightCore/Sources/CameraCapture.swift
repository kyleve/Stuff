import Foundation

/// A single shutter event contains a JPEG and, when supported, its unmodified RAW companion.
public struct CameraCapture: Sendable {
    public let jpeg: Data
    public let raw: Data?
    public init(jpeg: Data, raw: Data?) {
        self.jpeg = jpeg; self.raw = raw
    }
}
