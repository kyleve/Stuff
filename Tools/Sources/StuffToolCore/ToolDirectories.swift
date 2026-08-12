import Foundation

/// Resolves user-scoped command paths from the launch environment.
public struct ToolDirectories: Equatable, Sendable {
    public let home: URL
    public let temporary: URL

    public init(
        environment: [String: String],
        homeFallback: URL,
        temporaryFallback: URL,
    ) {
        home = Self.directory(
            environment["HOME"],
            fallback: homeFallback,
        )
        temporary = Self.directory(
            environment["TMPDIR"],
            fallback: temporaryFallback,
        )
    }

    private static func directory(_ path: String?, fallback: URL) -> URL {
        guard let path, path.isEmpty == false else { return fallback }
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
