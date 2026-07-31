import Foundation
@testable import Inspector
import Testing

struct InspectorSwiftDataStoreFamilyTests {
    @Test func erasesOnlyKnownStoreFamilyMembers() throws {
        let fixture = try StoreFamilyFixture()
        defer { fixture.cleanup() }
        let family = InspectorSwiftDataStoreFamily(
            storeURL: fixture.storeURL,
            storageRootURL: fixture.rootURL,
        )

        try family.erase(using: .default)

        for member in fixture.familyMembers {
            #expect(
                FileManager.default.fileExists(atPath: member.path(percentEncoded: false)) == false,
            )
        }
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.similarlyNamedFile.path(percentEncoded: false),
            ),
        )
    }

    @Test func refusesAStoreOutsideItsDeclaredRoot() throws {
        let fixture = try StoreFamilyFixture()
        let outside = try StoreFamilyFixture()
        defer {
            fixture.cleanup()
            outside.cleanup()
        }
        let family = InspectorSwiftDataStoreFamily(
            storeURL: outside.storeURL,
            storageRootURL: fixture.rootURL,
        )

        #expect(throws: InspectorSwiftDataStoreFamily.Failure.invalidConfiguration) {
            try family.erase(using: .default)
        }
        #expect(
            FileManager.default.fileExists(
                atPath: outside.storeURL.path(percentEncoded: false),
            ),
        )
    }

    @Test func refusesAStoreReachedThroughASymlinkOutsideItsDeclaredRoot() throws {
        let fixture = try StoreFamilyFixture()
        let outside = try StoreFamilyFixture()
        defer {
            fixture.cleanup()
            outside.cleanup()
        }
        let link = fixture.rootURL.appending(path: "linked-storage")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: outside.storeURL.deletingLastPathComponent(),
        )
        let linkedStore = link.appending(path: outside.storeURL.lastPathComponent)
        let family = InspectorSwiftDataStoreFamily(
            storeURL: linkedStore,
            storageRootURL: fixture.rootURL,
        )

        #expect(throws: InspectorSwiftDataStoreFamily.Failure.invalidConfiguration) {
            try family.erase(using: .default)
        }
        #expect(
            FileManager.default.fileExists(
                atPath: outside.storeURL.path(percentEncoded: false),
            ),
        )
    }

    @Test func cancellationBeforeErasureLeavesEveryMemberUntouched() async throws {
        let fixture = try StoreFamilyFixture()
        defer { fixture.cleanup() }
        let family = InspectorSwiftDataStoreFamily(
            storeURL: fixture.storeURL,
            storageRootURL: fixture.rootURL,
        )

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try family.erase(using: .default)
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        for member in fixture.familyMembers {
            #expect(
                FileManager.default.fileExists(atPath: member.path(percentEncoded: false)),
            )
        }
    }
}

private struct StoreFamilyFixture {
    let rootURL: URL
    let storeURL: URL
    let familyMembers: [URL]
    let similarlyNamedFile: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-store-family-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        let storage = rootURL.appending(path: "Storage", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        storeURL = storage.appending(path: "Periscope.store")
        let wal = storage.appending(path: "Periscope.store-wal")
        let shm = storage.appending(path: "Periscope.store-shm")
        let journal = storage.appending(path: "Periscope.store-journal")
        let support = storage.appending(
            path: "Periscope.store_SUPPORT",
            directoryHint: .isDirectory,
        )
        let cloudKitAssets = storage.appending(
            path: "Periscope.store_ckAssets",
            directoryHint: .isDirectory,
        )
        let cloudKitAssetFiles = storage.appending(
            path: "Periscope.store_ckAssetFiles",
            directoryHint: .isDirectory,
        )
        familyMembers = [
            storeURL,
            wal,
            shm,
            journal,
            support,
            cloudKitAssets,
            cloudKitAssetFiles,
        ]
        similarlyNamedFile = storage.appending(path: "Periscope.store-backup")

        for file in [storeURL, wal, shm, journal, similarlyNamedFile] {
            try Data(file.lastPathComponent.utf8).write(to: file)
        }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data("external".utf8).write(to: support.appending(path: "blob"))
        for directory in [cloudKitAssets, cloudKitAssetFiles] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
            try Data("asset".utf8).write(to: directory.appending(path: "blob"))
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
