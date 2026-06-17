import CodeGraphModel
import Foundation
import Observation

/// Owns the currently-loaded graph and keeps it in sync with the file on disk.
@MainActor
@Observable
final class GraphStore {
    private(set) var graph: CodeGraph?
    private(set) var sourceURL: URL?
    private(set) var loadError: String?
    private(set) var lastLoaded: Date?

    private let bookmark = GraphBookmark()
    private var watcher: FileWatcher?
    private var accessedURL: URL?

    /// Reopen the previously-selected file, if any, at launch.
    func restore() {
        guard graph == nil, let url = bookmark.resolve() else { return }
        load(url, persistBookmark: false)
    }

    /// Open a freshly user-selected file and remember it for next launch.
    func open(_ url: URL) {
        load(url, persistBookmark: true)
    }

    /// Re-read the current file (used by the watcher and the Reload command).
    func reload() {
        guard let url = sourceURL else { return }
        decode(from: url)
    }

    private func load(_ url: URL, persistBookmark: Bool) {
        releaseAccess()
        let accessed = url.startAccessingSecurityScopedResource()
        if accessed {
            accessedURL = url
        }
        if persistBookmark {
            bookmark.save(url)
        }
        sourceURL = url
        decode(from: url)
        guard loadError == nil else {
            return
        }
        startWatching(url)
    }

    private func decode(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            graph = try CodeGraph.decoded(from: data)
            loadError = nil
            lastLoaded = .now
        } catch {
            loadError = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func startWatching(_ url: URL) {
        watcher?.stop()
        let watcher = FileWatcher(url: url, debounce: 0.3) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        watcher.start()
        self.watcher = watcher
    }

    private func releaseAccess() {
        watcher?.stop()
        watcher = nil
        if let accessedURL {
            accessedURL.stopAccessingSecurityScopedResource()
        }
        accessedURL = nil
    }
}
