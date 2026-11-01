import Foundation

/// Validation fails atomically and reports a path within the authored document.
public struct ViewDocumentValidationError: Error, Equatable, Sendable, LocalizedError {
    public let path: String
    public let reason: String
    public var errorDescription: String? {
        "\(path): \(reason)"
    }
}
