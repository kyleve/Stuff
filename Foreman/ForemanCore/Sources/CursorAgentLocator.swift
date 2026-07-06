import Foundation

/// Resolves the `cursor-agent` executable.
///
/// GUI apps don't inherit the user's shell `PATH`, so the locator checks the
/// CLI's known install locations directly. An explicitly configured path is
/// validated rather than trusted, so a stale setting surfaces as a real error
/// instead of a confusing spawn failure.
public struct CursorAgentLocator: Sendable {
    /// The locations `cursor-agent` installs to, checked in order.
    public static let defaultSearchPaths = [
        "~/.local/bin/cursor-agent",
        "/usr/local/bin/cursor-agent",
        "/opt/homebrew/bin/cursor-agent",
    ]

    public struct NotFoundError: Error, LocalizedError, Equatable {
        /// The paths that were checked, in order.
        public let searchedPaths: [String]

        public init(searchedPaths: [String]) {
            self.searchedPaths = searchedPaths
        }

        public var errorDescription: String? {
            String(localized: .cursorAgentNotFound(paths: searchedPaths.joined(separator: ", ")))
        }
    }

    private let searchPaths: [String]

    public init() {
        searchPaths = Self.defaultSearchPaths
    }

    @_spi(Testing)
    public init(searchPaths: [String]) {
        self.searchPaths = searchPaths
    }

    /// The executable to spawn: `explicit` when set (validated), otherwise the
    /// first search path holding an executable file. Throws ``NotFoundError``
    /// when nothing usable exists.
    public func locate(explicit: URL?) throws -> URL {
        if let explicit {
            guard FileManager.default.isExecutableFile(atPath: explicit.path) else {
                throw NotFoundError(searchedPaths: [explicit.path])
            }
            return explicit
        }
        var searched: [String] = []
        for path in searchPaths {
            let expanded = (path as NSString).expandingTildeInPath
            searched.append(expanded)
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        throw NotFoundError(searchedPaths: searched)
    }
}
