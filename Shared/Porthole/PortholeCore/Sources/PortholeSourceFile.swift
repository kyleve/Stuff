import CryptoKit
import Foundation

/// Exact source text packaged by the binding generator for the installed build.
public struct PortholeSourceFile: Sendable, Equatable, Codable, Identifiable {
    public let path: String
    public let content: String
    public let sha256: String
    public var id: String {
        path
    }

    public init(path: String, content: String) {
        self.path = path
        self.content = content
        sha256 = Self.hash(content)
    }

    public var hasValidHash: Bool {
        sha256 == Self.hash(content)
    }

    private static func hash(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
