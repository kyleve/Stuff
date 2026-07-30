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
        let support = storage.appending(path: "default.store_SUPPORT", directoryHint: .isDirectory)
        try Data().write(to: store)
        try Data().write(to: wal)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data().write(to: support.appending(path: "external"))
        let fileSystem = InspectorFileSystem(
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
        for item in storageItems {
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
            protectedStoreURLs: [],
            unresolvedProtectionRoots: [],
        )

        await #expect(throws: InspectorFileSystemError.outsideContainer) {
            try await fileSystem.contents(of: link, in: fixture.container)
        }
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
