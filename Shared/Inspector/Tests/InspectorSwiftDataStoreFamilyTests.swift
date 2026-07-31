import Foundation
@testable import Inspector
import SwiftData
import Testing

struct InspectorSwiftDataStoreFamilyTests {
    @Test func erasesOnlyKnownStoreFamilyMembers() throws {
        let fixture = try StoreFamilyFixture()
        defer { fixture.cleanup() }
        let family = InspectorSwiftDataStoreFamily(
            storeURL: fixture.storeURL,
            storageRootURL: fixture.rootURL,
            recoveryStorageURLs: [],
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
            recoveryStorageURLs: [],
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
            recoveryStorageURLs: [],
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

    @Test func erasesOnlyExplicitlyConfiguredRecoveryStorage() throws {
        let fixture = try StoreFamilyFixture()
        defer { fixture.cleanup() }
        let recoveryURL = fixture.rootURL.appending(
            path: "Periscope-Journals",
            directoryHint: .isDirectory,
        )
        let unrelatedURL = fixture.rootURL.appending(
            path: "Other-Journals",
            directoryHint: .isDirectory,
        )
        for directory in [recoveryURL, unrelatedURL] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
            try Data("segment".utf8).write(to: directory.appending(path: "segment"))
        }
        let family = InspectorSwiftDataStoreFamily(
            storeURL: fixture.storeURL,
            storageRootURL: fixture.rootURL,
            recoveryStorageURLs: [recoveryURL],
        )

        try family.erase(using: .default)

        #expect(
            FileManager.default.fileExists(
                atPath: recoveryURL.path(percentEncoded: false),
            ) == false,
        )
        #expect(
            FileManager.default.fileExists(
                atPath: unrelatedURL.path(percentEncoded: false),
            ),
        )
    }

    @Test func refusesRecoveryStorageOutsideItsDeclaredRoot() throws {
        let fixture = try StoreFamilyFixture()
        let outside = try StoreFamilyFixture()
        defer {
            fixture.cleanup()
            outside.cleanup()
        }
        let family = InspectorSwiftDataStoreFamily(
            storeURL: fixture.storeURL,
            storageRootURL: fixture.rootURL,
            recoveryStorageURLs: [outside.rootURL],
        )

        #expect(throws: InspectorSwiftDataStoreFamily.Failure.invalidConfiguration) {
            try family.erase(using: .default)
        }
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.storeURL.path(percentEncoded: false),
            ),
        )
    }

    @Test func cancellationBeforeErasureLeavesEveryMemberUntouched() async throws {
        let fixture = try StoreFamilyFixture()
        defer { fixture.cleanup() }
        let family = InspectorSwiftDataStoreFamily(
            storeURL: fixture.storeURL,
            storageRootURL: fixture.rootURL,
            recoveryStorageURLs: [],
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

    @Test func corruptStoreCanBeDestroyedAndRecreatedWithSwiftData() throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-store-reopen-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let storeURL = rootURL.appending(path: "Periscope.store")
        try Data(repeating: 0xA5, count: 4_000_000).write(to: storeURL)

        do {
            _ = try makeContainer(at: storeURL)
            Issue.record("Expected the corrupt store to fail opening.")
        } catch {
            #expect(error.localizedDescription.isEmpty == false)
        }

        let family = InspectorSwiftDataStoreFamily(
            storeURL: storeURL,
            storageRootURL: rootURL,
            recoveryStorageURLs: [],
        )
        try family.erase(using: .default)

        let reopened = try makeContainer(at: storeURL)
        #expect(reopened.configurations.map(\.url) == [storeURL])
    }

    private func makeContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema([TestWidget.self])
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none,
        )
        return try ModelContainer(for: schema, configurations: [configuration])
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
            path: ".Periscope_SUPPORT",
            directoryHint: .isDirectory,
        )
        let legacySupport = storage.appending(
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
            legacySupport,
            cloudKitAssets,
            cloudKitAssetFiles,
        ]
        similarlyNamedFile = storage.appending(path: "Periscope.store-backup")

        for file in [storeURL, wal, shm, journal, similarlyNamedFile] {
            try Data(file.lastPathComponent.utf8).write(to: file)
        }
        for directory in [support, legacySupport, cloudKitAssets, cloudKitAssetFiles] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
            try Data("external".utf8).write(to: directory.appending(path: "blob"))
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
