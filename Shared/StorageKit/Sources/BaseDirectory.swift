import Foundation

/// Where a `.persistent` `StorageSystem` is rooted on disk.
///
/// Pick the standard search-path directory that fits the data: `applicationSupport`
/// (the default home for app-managed data), `caches` (purgeable), `documents`
/// (user-facing, backed up and visible in the Files app when the app opts in), or
/// `library`. `subdirectory` (optional) namespaces under the chosen directory so a
/// system isn't created at the very top of it. `custom(_:)` is the escape hatch for
/// the exceptional cases the standard directories don't cover — tests, relocations,
/// an App Group / security-scoped URL — and `resolvedURL(using:)` is public so a
/// caller can resolve a standard directory and build a `.custom` base from it.
///
/// Ignored entirely in `.inMemory` mode — there the system roots itself in a
/// temporary directory it owns and removes on `deleteAll()`.
public struct BaseDirectory: Sendable {
    private enum Root {
        case applicationSupport
        case caches
        case documents
        case library
        case custom(URL)
    }

    private let root: Root
    private let subdirectory: String?

    /// The app's Application Support directory, optionally namespaced by
    /// `subdirectory`. The default home for data your app creates and manages.
    public static func applicationSupport(subdirectory: String? = nil) -> BaseDirectory {
        BaseDirectory(root: .applicationSupport, subdirectory: subdirectory)
    }

    /// The app's Caches directory, optionally namespaced by `subdirectory`. The OS
    /// may purge it under storage pressure, so only put regenerable data here.
    public static func caches(subdirectory: String? = nil) -> BaseDirectory {
        BaseDirectory(root: .caches, subdirectory: subdirectory)
    }

    /// The app's Documents directory, optionally namespaced by `subdirectory`.
    /// User-facing: it's included in backups and shows up in the Files app when the
    /// app opts in (`UISupportsDocumentBrowser` / `LSSupportsOpeningDocumentsInPlace`).
    public static func documents(subdirectory: String? = nil) -> BaseDirectory {
        BaseDirectory(root: .documents, subdirectory: subdirectory)
    }

    /// The app's Library directory (the parent of Application Support and Caches),
    /// optionally namespaced by `subdirectory`. Prefer `applicationSupport` /
    /// `caches` unless you specifically need to root beside them.
    public static func library(subdirectory: String? = nil) -> BaseDirectory {
        BaseDirectory(root: .library, subdirectory: subdirectory)
    }

    /// An explicit directory URL for the exceptional cases the standard directories
    /// don't cover (tests, relocations, an App Group / security-scoped URL). Build
    /// one from a resolved standard directory via `resolvedURL(using:)`.
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
                try standardURL(.applicationSupportDirectory, using: fileManager)
            case .caches:
                try standardURL(.cachesDirectory, using: fileManager)
            case .documents:
                try standardURL(.documentDirectory, using: fileManager)
            case .library:
                try standardURL(.libraryDirectory, using: fileManager)
            case let .custom(url):
                url
        }
        guard let subdirectory, !subdirectory.isEmpty else { return base }
        return base.appending(path: subdirectory, directoryHint: .isDirectory)
    }

    private func standardURL(
        _ directory: FileManager.SearchPathDirectory,
        using fileManager: FileManager,
    ) throws -> URL {
        try fileManager.url(
            for: directory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true,
        )
    }
}
