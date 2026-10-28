import Foundation

/// The explicitly configured files that make up one on-disk SwiftData store.
///
/// Generic file browsing protects the wider prefix family conservatively. Raw
/// recovery erasure is intentionally narrower: only the known SQLite files and
/// SwiftData external-storage support directory, plus exact app-declared
/// recovery storage, are eligible.
struct InspectorSwiftDataStoreFamily {
    enum Failure: LocalizedError, Equatable {
        case invalidConfiguration
        case incompleteErasure([String])

        var errorDescription: String? {
            switch self {
                case .invalidConfiguration:
                    "The configured SwiftData store is outside its declared storage root."
                case let .incompleteErasure(memberNames):
                    """
                    The SwiftData store could not be fully deleted. Remaining items: \
                    \(memberNames.joined(separator: ", ")).
                    """
            }
        }
    }

    /// Exact app-owned auxiliary storage that must be removed with a complete
    /// store erase, independently of whether raw recovery has a store URL.
    struct RecoveryStorage {
        let storageRootURL: URL
        let urls: [URL]

        init(storageRootURL: URL, urls: [URL]) {
            self.storageRootURL = storageRootURL.standardizedFileURL
            self.urls = urls.map(\.standardizedFileURL)
        }

        func erase(using fileManager: FileManager) throws {
            try validate()

            for url in urls where fileManager.fileExists(
                atPath: url.path(percentEncoded: false),
            ) {
                try fileManager.removeItem(at: url)
            }

            let remainingMemberNames = urls.compactMap { member -> String? in
                guard fileManager.fileExists(atPath: member.path(percentEncoded: false)) else {
                    return nil
                }
                return member.lastPathComponent
            }
            guard remainingMemberNames.isEmpty else {
                throw Failure.incompleteErasure(remainingMemberNames)
            }
        }

        func validate() throws {
            let resolvedRoot = storageRootURL.resolvingSymlinksInPath()
            for url in urls {
                let resolvedURL = url.resolvingSymlinksInPath()
                let resolvedParent = url.deletingLastPathComponent()
                    .resolvingSymlinksInPath()
                let resolvedParentIsInsideRoot = resolvedParent == resolvedRoot
                    || resolvedParent.isDescendant(of: resolvedRoot)
                guard url.isFileURL,
                      url != storageRootURL,
                      url.isDescendant(of: storageRootURL),
                      resolvedURL.isDescendant(of: resolvedRoot),
                      resolvedParentIsInsideRoot
                else {
                    throw Failure.invalidConfiguration
                }
            }
        }
    }

    let storeURL: URL
    let storageRootURL: URL
    let recoveryStorage: RecoveryStorage

    init(
        storeURL: URL,
        storageRootURL: URL,
        recoveryStorageURLs: [URL],
    ) {
        self.storeURL = storeURL.standardizedFileURL
        self.storageRootURL = storageRootURL.standardizedFileURL
        recoveryStorage = RecoveryStorage(
            storageRootURL: storageRootURL,
            urls: recoveryStorageURLs,
        )
    }

    func erase(using fileManager: FileManager) throws {
        try Task.checkCancellation()
        try validate()

        let parent = storeURL.deletingLastPathComponent()
        let memberNames = Self.knownMemberNames(for: storeURL)
        let memberNameSet = Set(memberNames)
        let storeMembers: [URL] = if fileManager
            .fileExists(atPath: parent.path(percentEncoded: false))
        {
            try fileManager.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: nil,
            )
            .filter { memberNameSet.contains($0.lastPathComponent) }
        } else {
            []
        }
        let recoveryMembers = recoveryStorage.urls.filter {
            fileManager.fileExists(atPath: $0.path(percentEncoded: false))
        }
        let members = Array(Set(storeMembers + recoveryMembers))
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

        let knownMembers = memberNames.map { parent.appending(path: $0) }
            + recoveryStorage.urls
        let remainingMemberNames = knownMembers.compactMap { member -> String? in
            guard fileManager.fileExists(atPath: member.path(percentEncoded: false)) else {
                return nil
            }
            return member.lastPathComponent
        }
        guard remainingMemberNames.isEmpty else {
            throw Failure.incompleteErasure(remainingMemberNames)
        }
    }

    /// Delete only the app-declared auxiliary recovery storage, leaving the
    /// SQLite family for `ModelContainer.erase()` to manage while a store is
    /// open.
    func eraseRecoveryStorage(using fileManager: FileManager) throws {
        try recoveryStorage.erase(using: fileManager)
    }

    /// Exact family names SwiftData has used beside a configured SQLite store.
    /// Shared by recovery deletion and generic-file protection so support paths
    /// cannot be deletable merely because their OS-specific name changed shape.
    static func knownMemberNames(for storeURL: URL) -> [String] {
        let storeName = storeURL.lastPathComponent
        let configurationName = storeURL.deletingPathExtension().lastPathComponent
        return [
            storeName,
            "\(storeName)-wal",
            "\(storeName)-shm",
            "\(storeName)-journal",
            // SwiftData's external-storage directory is named from the
            // configuration (`.Periscope_SUPPORT` for `Periscope.store`),
            // not from the complete SQLite filename. Keep the older explicit
            // filename variants too for stores produced by other OS releases.
            ".\(configurationName)_SUPPORT",
            ".\(configurationName)_ckAssets",
            ".\(configurationName)_ckAssetFiles",
            "\(storeName)_SUPPORT",
            "\(storeName)_ckAssets",
            "\(storeName)_ckAssetFiles",
        ]
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
        try recoveryStorage.validate()
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
        let knownMemberNames = Set(InspectorSwiftDataStoreFamily.knownMemberNames(for: storeURL))
        return familyMember.hasPrefix(storeURL.lastPathComponent)
            || knownMemberNames.contains(familyMember)
    }
}
