import Foundation

public protocol ReviewWorkspaceStorage: Sendable {
    func scan(root: URL) async throws -> [SnapshotSuite]
    func save(
        _ document: ReviewDocument,
        suite: URL,
        expected: Data?,
        image: SnapshotImage,
    ) async throws -> ReviewFile
}

/// Off-main-actor discovery and serialized review writes. No rendering or UI dependencies.
public actor ReviewWorkspaceStore: ReviewWorkspaceStorage {
    public init() {}

    public func scan(root: URL) throws -> [SnapshotSuite] {
        let manager = FileManager.default
        var paths: [URL: [URL]] = [:]
        var enumerationError: (any Error)?
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            },
        ) else { throw ReviewError.unavailableImage("The selected folder cannot be read.") }
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true,
                  url.pathExtension.lowercased() == "png" || [
                      SnapshotManifest.filename,
                      ReviewDocument.filename,
                  ].contains(url.lastPathComponent),
                  let marker = url.pathComponents.lastIndex(of: "__Snapshots__"),
                  marker + 2 < url.pathComponents.count
            else { continue }
            let suite = URL(
                fileURLWithPath: NSString
                    .path(withComponents: Array(url.pathComponents.prefix(marker + 2))),
                isDirectory: true,
            )
            guard suite.path == root.path || suite.path.hasPrefix(root.path + "/") else {
                throw ReviewError
                    .unavailableImage(
                        "Select the suite folder or an ancestor so its review file is included in folder access.",
                    )
            }
            if url.pathExtension.lowercased() == "png" { paths[suite, default: []].append(url) }
            else if paths[suite] == nil { paths[suite] = [] }
        }
        if let enumerationError { throw enumerationError }
        return try paths.keys.sorted(by: { $0.path < $1.path }).map { suite in
            try Task.checkCancellation()
            var manifest: SnapshotManifest?
            var manifestError: (any Error)?
            let manifestURL = suite.appendingPathComponent(SnapshotManifest.filename)
            if manager.fileExists(atPath: manifestURL.path) {
                do {
                    let decoded = try ReviewJSON.decode(
                        SnapshotManifest.self,
                        from: Data(contentsOf: manifestURL),
                    )
                    try decoded.validate()
                    manifest = decoded
                } catch { manifestError = error }
            }
            let images = try paths[suite, default: []].sorted(by: { $0.path < $1.path })
                .map { url in
                    try Task.checkCancellation()
                    let path = try SnapshotPath(String(url.path.dropFirst(suite.path.count + 1)))
                    return SnapshotImage(
                        id: .init(suite: suite, path: path),
                        metadata: manifest?.entries.first { $0.path == path },
                        content: Result { try ReviewFileStore.inspect(url) },
                    )
                }
            return SnapshotSuite(
                id: suite,
                name: suite.path.replacingOccurrences(of: root.path + "/", with: ""),
                images: images,
                reviews: Result { try ReviewFileStore.read(suite) },
                manifestError: manifestError,
            )
        }
    }

    public func save(
        _ document: ReviewDocument,
        suite: URL,
        expected: Data?,
        image: SnapshotImage,
    ) throws -> ReviewFile {
        let expectedImage = try image.content.get()
        let current = try ReviewFileStore.inspect(image.url)
        guard expectedImage.fingerprint == current.fingerprint
        else { throw ReviewError.imageChanged }
        return try ReviewFileStore.save(document, suite: suite, expected: expected)
    }
}
