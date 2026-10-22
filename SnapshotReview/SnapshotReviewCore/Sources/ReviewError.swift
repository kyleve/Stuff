import Foundation

public enum ReviewError: Error, LocalizedError, Sendable {
    case invalidPath(String)
    case unsupportedVersion(Int)
    case invalidDocument(String)
    case externalChange
    case imageChanged
    case unavailableImage(String)

    public var errorDescription: String? {
        switch self {
            case let .invalidPath(path): "Invalid relative image path: \(path)"
            case let .unsupportedVersion(version): "This file uses unsupported format version \(version)."
            case let .invalidDocument(reason): "Invalid review file: \(reason)"
            case .externalChange: "The review file changed outside this app. Reload it before saving. Your draft is retained."
            case .imageChanged: "The image changed during review. Refresh and inspect the current image before saving."
            case let .unavailableImage(reason): reason
        }
    }
}
