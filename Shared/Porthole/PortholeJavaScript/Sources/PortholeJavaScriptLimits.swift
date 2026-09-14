import Foundation

/// Bounds one console evaluation, including its pending native operations.
public struct PortholeJavaScriptLimits: Sendable, Equatable {
    public var heapBytes: Int
    public var stackBytes: Int
    public var sourceBytes: Int
    public var valueBytes: Int
    public var nativeCalls: Int
    public var duration: Duration

    public init(
        heapBytes: Int,
        stackBytes: Int,
        sourceBytes: Int,
        valueBytes: Int,
        nativeCalls: Int,
        duration: Duration,
    ) {
        self.heapBytes = heapBytes
        self.stackBytes = stackBytes
        self.sourceBytes = sourceBytes
        self.valueBytes = valueBytes
        self.nativeCalls = nativeCalls
        self.duration = duration
    }

    public static let interactive = PortholeJavaScriptLimits(
        heapBytes: 32 * 1024 * 1024,
        stackBytes: 512 * 1024,
        sourceBytes: 256 * 1024,
        valueBytes: 1024 * 1024,
        nativeCalls: 128,
        duration: .seconds(30),
    )

    var isValid: Bool {
        heapBytes > 0 && stackBytes > 0 && sourceBytes > 0 && valueBytes > 0
            && nativeCalls > 0 && duration > .zero
    }
}
