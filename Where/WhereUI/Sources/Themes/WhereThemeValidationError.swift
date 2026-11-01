import Foundation
import ViewDocumentCore

/// A theme schema or appearance failure with an author-facing field path.
public struct WhereThemeValidationError: Error, LocalizedError, Equatable, Sendable {
    public let path: String
    public let reason: String
    public let underlying: ViewDocumentValidationError?
    public var errorDescription: String? {
        "\(path): \(reason)"
    }

    init(path: String, reason: String) {
        self.path = path
        self.reason = reason
        underlying = nil
    }

    init(path: String, underlying: ViewDocumentValidationError) {
        self.path = path
        reason = underlying.reason
        self.underlying = underlying
    }
}
