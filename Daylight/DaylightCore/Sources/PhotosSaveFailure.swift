import Foundation

/// Use only when the saver can prove no asset was created. Other errors remain uncertain.
public struct PhotosSaveFailure: Error, LocalizedError, Sendable {
    public let message: String
    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
