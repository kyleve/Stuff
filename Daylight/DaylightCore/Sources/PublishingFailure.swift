import Foundation

public enum PublishingFailure: Error, Sendable {
    case retry(after: Date, message: String)
    case needsAttention(String)
}
