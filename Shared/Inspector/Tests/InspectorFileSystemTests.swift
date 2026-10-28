import Foundation
@testable import Inspector
import Testing

struct InspectorFileSystemTests {
    @Test func listsHiddenItemsAndRecursivelyDeletesDirectories() async throws {
        let fixture = try DirectoryFixture()
        defer { fixture.cleanup() }
        let nested = fixture.root.appending(path: "folder/child", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true,
        )
        try Data("payload".utf8).write(to: nested.appending(path: ".hidden"))
        let fileSystem = InspectorFileSystem(
            configuredContainerRoots: [fixture.root],
            protectedStoreURLs: [],
            unresolvedProtectionRoots: [],
        )

        let rootItems = try await fileSystem.contents(
            of: fixture.root,
            in: fixture.container,
        )
        let folder = try #require(rootItems.first { $0.name == "folder" })
        let childItems = try await fileSystem.contents(
            of: nested,
            in: fixture.container,
        )

        #expect(childItems.first?.name == ".hidden")
        #expect(childItems.first?.isHidden == true)
        try await fileSystem.delete(folder, in: fixture.container)
        #expect(!FileManager.default.fileExists(atPath: folder.url.path()))
    }

    @Test func refusesConfiguredRootAndPathsOutsideIt() async throws {
        let fixture = try DirectoryFixture()
        defer { fixture.cleanup() }
        let fileSystem = InspectorFileSystem(
            configuredContainerRoots: [fixture.root],
            protectedStoreURLs: [],
            unresolvedProtectionRoots: [],
        )
        let rootItem = InspectorFileItem(
            url: fixture.root,
            isDirectory: true,
            isSymbolicLink: false,
            isHidden: false,
            byteCount: nil,
            modificationDate: nil,
            deletionProhibition: nil,
        )

        await #expect(throws: InspectorFileSystemError.containerRoot) {
            try await fileSystem.delete(rootItem, in: fixture.container)
        }
        await #expect(throws: InspectorFileSystemError.outsideContainer) {
            try await fileSystem.contents(
                of: fixture.root.deletingLastPathComponent(),
                in: fixture.container,
            )
        }
    }

    @Test func protectsStoreFilesSidecarsSupportTreesAndTheirAncestors() async throws {
        let fixture = try DirectoryFixture()
        defer { fixture.cleanup() }
        let storage = fixture.root.appending(path: "Storage", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let store = storage.appending(path: "default.store")
        let wal = storage.appending(path: "default.store-wal")
        let hiddenSupport = storage.appending(
            path: ".default_SUPPORT",
            directoryHint: .isDirectory,
        )
        let hiddenCloudKitAssets = storage.appending(
            path: ".default_ckAssets",
            directoryHint: .isDirectory,
        )
        let hiddenCloudKitAssetFiles = storage.appending(
            path: ".default_ckAssetFiles",
            directoryHint: .isDirectory,
        )
        try Data().write(to: store)
        try Data().write(to: wal)
        for directory in [hiddenSupport, hiddenCloudKitAssets, hiddenCloudKitAssetFiles] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
            try Data().write(to: directory.appending(path: "external"))
        }
        let fileSystem = InspectorFileSystem(
            configuredContainerRoots: [fixture.root],
            protectedStoreURLs: [store],
            unresolvedProtectionRoots: [],
        )
        let rootItems = try await fileSystem.contents(
            of: fixture.root,
            in: fixture.container,
        )
        let storageItem = try #require(rootItems.first { $0.url == storage })
        let storageItems = try await fileSystem.contents(
            of: storage,
            in: fixture.container,
        )

        #expect(storageItem.deletionProhibition != nil)
        #expect(storageItems.allSatisfy { $0.deletionProhibition != nil })
        let supportItems = try await fileSystem.contents(
            of: hiddenSupport,
            in: fixture.container,
        )
        #expect(supportItems.allSatisfy { $0.deletionProhibition != nil })
        for item in storageItems {
            await #expect(throws: InspectorFileSystemError.protectedSwiftDataStore) {
                try await fileSystem.delete(item, in: fixture.container)
            }
        }
        for item in supportItems {
            await #expect(throws: InspectorFileSystemError.protectedSwiftDataStore) {
                try await fileSystem.delete(item, in: fixture.container)
            }
        }
        await #expect(throws: InspectorFileSystemError.protectedSwiftDataStore) {
            try await fileSystem.delete(storageItem, in: fixture.container)
        }
    }

    @Test func unresolvedStoreDisablesDeletionAcrossItsContainingTreeOnly() async throws {
        let fixture = try DirectoryFixture()
        defer { fixture.cleanup() }
        let storage = fixture.root.appending(path: "Storage", directoryHint: .isDirectory)
        let unrelated = fixture.root.appending(path: "Unrelated")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try Data().write(to: unrelated)
        let fileSystem = InspectorFileSystem(
            configuredContainerRoots: [fixture.root],
            protectedStoreURLs: [],
            unresolvedProtectionRoots: [storage],
        )
        let items = try await fileSystem.contents(of: fixture.root, in: fixture.container)
        let storageItem = try #require(items.first { $0.url == storage })
        let unrelatedItem = try #require(items.first { $0.url == unrelated })

        #expect(storageItem.deletionProhibition != nil)
        #expect(unrelatedItem.deletionProhibition == nil)
        await #expect(throws: InspectorFileSystemError.protectionUnavailable) {
            try await fileSystem.delete(storageItem, in: fixture.container)
        }
        try await fileSystem.delete(unrelatedItem, in: fixture.container)
        #expect(!FileManager.default.fileExists(atPath: unrelated.path()))
    }

    @Test func refusesToBrowseThroughASymlinkOutsideTheContainer() async throws {
        let fixture = try DirectoryFixture()
        let outside = try DirectoryFixture()
        defer {
            fixture.cleanup()
            outside.cleanup()
        }
        let link = fixture.root.appending(path: "outside-link")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: outside.root,
        )
        let fileSystem = InspectorFileSystem(
            configuredContainerRoots: [fixture.root],
            protectedStoreURLs: [],
            unresolvedProtectionRoots: [],
        )
        let rootItems = try await fileSystem.contents(
            of: fixture.root,
            in: fixture.container,
        )
        let linkItem = try #require(rootItems.first { $0.name == link.lastPathComponent })

        await #expect(throws: InspectorFileSystemError.outsideContainer) {
            try await fileSystem.contents(of: link, in: fixture.container)
        }
        await #expect(throws: InspectorFileSystemError.outsideContainer) {
            try await fileSystem.previewURL(for: linkItem, in: fixture.container)
        }
    }

    @Test func protectsNestedConfiguredRootsAndTheirAncestors() async throws {
        let fixture = try DirectoryFixture()
        defer { fixture.cleanup() }
        let parent = fixture.root.appending(path: "Parent", directoryHint: .isDirectory)
        let nestedRoot = parent.appending(path: "Nested", directoryHint: .isDirectory)
        let sibling = fixture.root.appending(path: "sibling")
        try FileManager.default.createDirectory(
            at: nestedRoot,
            withIntermediateDirectories: true,
        )
        try Data("keep".utf8).write(to: nestedRoot.appending(path: "value"))
        try Data("delete".utf8).write(to: sibling)
        let nestedContainer = InspectorConfiguration.FileContainer(
            id: .init(rawValue: "nested"),
            title: "Nested",
            rootURL: nestedRoot,
        )
        let fileSystem = InspectorFileSystem(
            configuredContainerRoots: [fixture.root, nestedContainer.rootURL],
            protectedStoreURLs: [],
            unresolvedProtectionRoots: [],
        )
        let rootItems = try await fileSystem.contents(of: fixture.root, in: fixture.container)
        let parentItem = try #require(rootItems.first { $0.name == "Parent" })
        let siblingItem = try #require(rootItems.first { $0.name == "sibling" })
        let parentItems = try await fileSystem.contents(of: parent, in: fixture.container)
        let nestedItem = try #require(parentItems.first { $0.name == "Nested" })

        #expect(parentItem.deletionProhibition != nil)
        #expect(nestedItem.deletionProhibition != nil)
        await #expect(throws: InspectorFileSystemError.containerRoot) {
            try await fileSystem.delete(parentItem, in: fixture.container)
        }
        await #expect(throws: InspectorFileSystemError.containerRoot) {
            try await fileSystem.delete(nestedItem, in: fixture.container)
        }
        try await fileSystem.delete(siblingItem, in: fixture.container)
        #expect(FileManager.default.fileExists(atPath: sibling.path()) == false)
    }
}

private struct DirectoryFixture {
    let root: URL
    let container: InspectorConfiguration.FileContainer

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "inspector-files-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        container = InspectorConfiguration.FileContainer(
            id: .init(rawValue: "test"),
            title: "Test",
            rootURL: root,
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
