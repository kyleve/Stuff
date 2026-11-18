import Foundation

extension StorageContainer {
    /// The raw-file namespace for this container: URLs for files kept directly in
    /// the container's own directory. See ``FileStorage``.
    public nonisolated var files: FileStorage {
        FileStorage(container: self)
    }
}

/// The `files` namespace of a ``StorageContainer`` — a tiny `Sendable` facade for
/// raw files stored directly in the container's directory. Vend it with
/// `container.files`.
public struct FileStorage: Sendable {
    let container: StorageContainer

    /// A URL for a raw file named `name` directly inside the container's directory.
    /// The directory already exists for a live container; writing the file is the
    /// caller's job.
    ///
    /// - Warning: This is pure path construction — it can't read the node's state,
    ///   so it neither checks liveness nor ensures the directory exists. On an
    ///   `inactive` node the directory is absent until the next vend reactivates
    ///   it, and on a `deleted` one it's gone for good; in both cases the returned
    ///   URL points into a missing directory and writes will fail. Only use the URL
    ///   while the container is live.
    public func url(_ name: String) -> URL {
        container.url.appending(path: name, directoryHint: .notDirectory)
    }
}
