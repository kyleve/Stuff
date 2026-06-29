import Foundation

/// Where a `.persistent` `StorageSystem` is rooted on disk.
///
/// `subdirectory` (optional) namespaces under the standard directory so a system
/// isn't created at the very top of Application Support / Caches; `custom(_:)` is
/// for tests and relocations. `resolvedURL(using:)` is public so a caller can
/// resolve a standard directory and build a `.custom` base from it.
///
/// Ignored entirely in `.inMemory` mode — there the system roots itself in a
/// temporary directory it owns and removes on `deleteAll()`.
public struct BaseDirectory: Sendable {
    private enum Root {
        case applicationSupport
        case caches
        case custom(URL)
    }

    private let root: Root
    private let subdirectory: String?

    /// The app's Application Support directory, optionally namespaced by
    /// `subdirectory`.
    public static func applicationSupport(subdirectory: String? = nil) -> BaseDirectory {
        BaseDirectory(root: .applicationSupport, subdirectory: subdirectory)
    }

    /// The app's Caches directory, optionally namespaced by `subdirectory`.
    public static func caches(subdirectory: String? = nil) -> BaseDirectory {
        BaseDirectory(root: .caches, subdirectory: subdirectory)
    }

    /// An explicit directory URL (tests, relocations). Build one from a resolved
    /// standard directory via `resolvedURL(using:)`.
    public static func custom(_ url: URL) -> BaseDirectory {
        BaseDirectory(root: .custom(url), subdirectory: nil)
    }

    /// Resolve to a concrete directory URL, creating the standard search-path
    /// directory if needed.
    ///
    /// The optional `subdirectory` is appended but not created here — the
    /// `StorageSystem` creates its namespace directory (and any intermediates)
    /// underneath it.
    public func resolvedURL(using fileManager: FileManager = .default) throws -> URL {
        let base: URL = switch root {
            case .applicationSupport:
                try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true,
                )
            case .caches:
                try fileManager.url(
                    for: .cachesDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true,
                )
            case let .custom(url):
                url
        }
        guard let subdirectory, !subdirectory.isEmpty else { return base }
        return base.appending(path: subdirectory, directoryHint: .isDirectory)
    }
}
