#if DEBUG
    /// The amount of a registered screen that a web export captures.
    public enum FlyoverCaptureExtent: String, Codable, CaseIterable, Sendable {
        case viewport
        case intrinsic
        case fullContent
        case fullContent2D
    }
#endif
