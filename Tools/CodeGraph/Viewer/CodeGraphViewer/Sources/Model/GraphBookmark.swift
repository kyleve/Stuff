import Foundation

/// Persists a security-scoped bookmark to the user-selected graph.json so the
/// sandboxed viewer can reopen it on the next launch without re-prompting.
struct GraphBookmark {
    private let key = "graph.bookmark"
    private let defaults = UserDefaults.standard

    func save(_ url: URL) {
        guard let data = try? url.bookmarkData(
            options: creationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil,
        ) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    /// Resolve the saved bookmark, refreshing it if the system reports it stale.
    /// The returned URL still needs `startAccessingSecurityScopedResource()`.
    func resolve() -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale,
        ) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        if isStale {
            save(url)
        }
        return url
    }

    private var creationOptions: URL.BookmarkCreationOptions {
        #if targetEnvironment(macCatalyst) || os(macOS)
            [.withSecurityScope]
        #else
            []
        #endif
    }

    private var resolutionOptions: URL.BookmarkResolutionOptions {
        #if targetEnvironment(macCatalyst) || os(macOS)
            [.withSecurityScope]
        #else
            []
        #endif
    }
}
