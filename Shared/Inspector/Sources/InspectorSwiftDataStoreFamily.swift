import Foundation

/// The explicitly configured files that make up one on-disk SwiftData store.
///
/// Generic file browsing protects the wider prefix family conservatively. Raw
/// recovery erasure is intentionally narrower: only the known SQLite files and
/// SwiftData external-storage support directory are eligible.
struct InspectorSwiftDataStoreFamily {
    enum Failure: LocalizedError, Equatable {
        case invalidConfiguration

        var errorDescription: String? {
            switch self {
                case .invalidConfiguration:
                    "The configured SwiftData store is outside its declared storage root."
            }
        }
    }

    let storeURL: URL
    let storageRootURL: URL

    init(storeURL: URL, storageRootURL: URL) {
        self.storeURL = storeURL.standardizedFileURL
        self.storageRootURL = storageRootURL.standardizedFileURL
    }

    func erase(using fileManager: FileManager) throws {
        try Task.checkCancellation()
        try validate()

        let parent = storeURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parent.path(percentEncoded: false)) else {
            return
        }

        let memberNames = Set([
            storeURL.lastPathComponent,
            "\(storeURL.lastPathComponent)-wal",
            "\(storeURL.lastPathComponent)-shm",
            "\(storeURL.lastPathComponent)-journal",
            "\(storeURL.lastPathComponent)_SUPPORT",
            "\(storeURL.lastPathComponent)_ckAssets",
            "\(storeURL.lastPathComponent)_ckAssetFiles",
        ])
        let members = try fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: nil,
        )
        .filter { memberNames.contains($0.lastPathComponent) }
        .sorted { left, right in
            // Keep the primary database until every sidecar/support item has
            // been removed successfully.
            if left.standardizedFileURL == storeURL {
                return false
            }
            if right.standardizedFileURL == storeURL {
                return true
            }
            return left.lastPathComponent < right.lastPathComponent
        }

        // Once erasure starts it runs to completion even if the calling view
        // disappears; cancellation is checked before the first destructive
        // operation, never between members.
        for member in members {
            try fileManager.removeItem(at: member)
        }
    }

    private func validate() throws {
        let parent = storeURL.deletingLastPathComponent()
        let resolvedRoot = storageRootURL.resolvingSymlinksInPath()
        let resolvedParent = parent.resolvingSymlinksInPath()
        guard storeURL.isFileURL,
              storageRootURL.isFileURL,
              storeURL != storageRootURL,
              storeURL.isDescendant(of: storageRootURL),
              resolvedParent == resolvedRoot || resolvedParent.isDescendant(of: resolvedRoot)
        else {
            throw Failure.invalidConfiguration
        }
    }
}

extension URL {
    func isDescendant(of root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = standardizedFileURL.pathComponents
        return components.count > rootComponents.count
            && Array(components.prefix(rootComponents.count)) == rootComponents
    }

    func isAncestor(of other: URL) -> Bool {
        other.isDescendant(of: self)
    }

    func belongsToSwiftDataStoreFamily(of storeURL: URL) -> Bool {
        if self == storeURL || isAncestor(of: storeURL) {
            return true
        }

        let storeParent = storeURL.deletingLastPathComponent()
        guard self == storeParent || isDescendant(of: storeParent) else {
            return false
        }
        let relativeComponents = Array(
            standardizedFileURL.pathComponents.dropFirst(storeParent.pathComponents.count),
        )
        guard let familyMember = relativeComponents.first else {
            return false
        }
        return familyMember.hasPrefix(storeURL.lastPathComponent)
    }
}
