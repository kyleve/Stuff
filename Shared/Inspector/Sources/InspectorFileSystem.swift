import Foundation

struct InspectorFileItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let isHidden: Bool
    let byteCount: Int?
    let modificationDate: Date?
    let deletionProhibition: String?

    var id: URL {
        url
    }

    var name: String {
        url.lastPathComponent
    }
}

enum InspectorFileSystemError: LocalizedError, Equatable {
    case outsideContainer
    case containerRoot
    case protectedSwiftDataStore
    case protectionUnavailable

    var errorDescription: String? {
        switch self {
            case .outsideContainer:
                "The selected item is outside its configured container."
            case .containerRoot:
                "Inspector cannot delete a configured container root."
            case .protectedSwiftDataStore:
                "This item contains an open SwiftData store. Erase it from the SwiftData tool."
            case .protectionUnavailable:
                "SwiftData protection could not be resolved for this container, so deletion is disabled."
        }
    }
}

/// Performs all directory enumeration and deletion away from the main actor and
/// owns the path-containment rules for destructive operations.
actor InspectorFileSystem {
    private let configuredContainerRoots: [URL]
    private let protectedStoreURLs: [URL]
    private let unresolvedProtectionRoots: [URL]
    private let fileManager: FileManager

    init(
        configuredContainerRoots: [URL],
        protectedStoreURLs: [URL],
        unresolvedProtectionRoots: [URL],
        fileManager: FileManager = .default,
    ) {
        self.configuredContainerRoots = configuredContainerRoots.map(\.standardizedFileURL)
        self.protectedStoreURLs = protectedStoreURLs.map(\.standardizedFileURL)
        self.unresolvedProtectionRoots = unresolvedProtectionRoots.map(\.standardizedFileURL)
        self.fileManager = fileManager
    }

    func contents(
        of directory: URL,
        in container: InspectorConfiguration.FileContainer,
    ) throws -> [InspectorFileItem] {
        try validate(directory, isInside: container.rootURL)
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return []
        }
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [],
        )
        return try urls.map { url in
            let values = try url.resourceValues(forKeys: Set(keys))
            return InspectorFileItem(
                url: url.standardizedFileURL,
                isDirectory: values.isDirectory == true,
                isSymbolicLink: values.isSymbolicLink == true,
                isHidden: values.isHidden == true,
                byteCount: values.fileSize,
                modificationDate: values.contentModificationDate,
                deletionProhibition: deletionError(
                    for: url.standardizedFileURL,
                    containerRoot: container.rootURL,
                )?.localizedDescription,
            )
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func delete(
        _ item: InspectorFileItem,
        in container: InspectorConfiguration.FileContainer,
    ) throws {
        let target = item.url.standardizedFileURL
        let root = container.rootURL.standardizedFileURL
        if let error = deletionError(for: target, containerRoot: root) {
            throw error
        }
        try fileManager.removeItem(at: target)
    }

    /// Resolve a Quick Look target only after applying the same canonical-root
    /// containment rule used by browsing and deletion.
    func previewURL(
        for item: InspectorFileItem,
        in container: InspectorConfiguration.FileContainer,
    ) throws -> URL {
        try validate(item.url, isInside: container.rootURL)
        return item.url.resolvingSymlinksInPath()
    }

    private func validate(_ url: URL, isInside root: URL) throws {
        if let error = containmentError(for: url, containerRoot: root) {
            throw error
        }
    }

    private func deletionError(
        for target: URL,
        containerRoot root: URL,
    ) -> InspectorFileSystemError? {
        if let error = containmentError(for: target, containerRoot: root) {
            return error
        }
        if target.standardizedFileURL == root.standardizedFileURL
            || configuredContainerRoots.contains(where: { configuredRoot in
                target == configuredRoot || target.isAncestor(of: configuredRoot)
            })
        {
            return .containerRoot
        }
        if unresolvedProtectionRoots.contains(where: { unresolvedRoot in
            target == unresolvedRoot
                || target.isDescendant(of: unresolvedRoot)
                || target.isAncestor(of: unresolvedRoot)
        }) {
            return .protectionUnavailable
        }
        if protectedStoreURLs.contains(where: { storeURL in
            target.belongsToSwiftDataStoreFamily(of: storeURL)
        }) {
            return .protectedSwiftDataStore
        }
        return nil
    }

    private func containmentError(
        for url: URL,
        containerRoot root: URL,
    ) -> InspectorFileSystemError? {
        let standardizedURL = url.standardizedFileURL
        let standardizedRoot = root.standardizedFileURL
        let resolvedURL = standardizedURL.resolvingSymlinksInPath()
        let resolvedRoot = standardizedRoot.resolvingSymlinksInPath()
        guard standardizedURL == standardizedRoot
            || standardizedURL.isDescendant(of: standardizedRoot),
            resolvedURL == resolvedRoot || resolvedURL.isDescendant(of: resolvedRoot)
        else {
            return .outsideContainer
        }
        return nil
    }
}
