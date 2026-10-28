import Foundation
@testable import Inspector
import SwiftData
import Testing

@MainActor
struct InspectorModelTests {
    @Test func failedSwiftDataSourceRemainsConfiguredWithDegradedState() async throws {
        let modeFixture = try InspectorModeControllerFixture()
        defer { modeFixture.cleanup() }
        let source = InspectorConfiguration.SwiftDataSource(
            id: .init(rawValue: "incompatible"),
            title: "Incompatible Store",
            storageRootURL: FileManager.default.temporaryDirectory,
            makeContainer: { throw IncompatibleStoreError() },
        )
        let model = InspectorModel(configuration: InspectorConfiguration(
            title: "Inspector",
            fileContainers: [],
            defaultsDomains: [],
            swiftDataSources: [source],
        ), modeController: modeFixture.controller)

        await model.prepare()

        #expect(model.preparationState == .ready)
        #expect(model.configuration.swiftDataSources.map(\.id) == [source.id])
        #expect(model.visibleSwiftDataSources.map(\.id) == [source.id])
        #expect(model.loadedSwiftDataSources[source.id] == nil)
        #expect(model.swiftDataFailures[source.id]?.isEmpty == false)
        #expect(model.fileSystem != nil)
    }

    @Test func erasesAnUnreadableStoreFamilyAndRemovesTheSource() async throws {
        let modeFixture = try InspectorModeControllerFixture()
        defer { modeFixture.cleanup() }
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-model-erase-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let storeURL = rootURL.appending(path: "broken.store")
        let walURL = rootURL.appending(path: "broken.store-wal")
        let recoveryURL = rootURL.appending(
            path: "Broken-Journals",
            directoryHint: .isDirectory,
        )
        let similarlyNamedURL = rootURL.appending(path: "broken.store-backup")
        try Data("broken".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: walURL)
        try FileManager.default.createDirectory(
            at: recoveryURL,
            withIntermediateDirectories: true,
        )
        try Data("journal".utf8).write(to: recoveryURL.appending(path: "segment"))
        try Data("keep".utf8).write(to: similarlyNamedURL)
        let container = InspectorConfiguration.FileContainer(
            id: .init(rawValue: "storage"),
            title: "Storage",
            rootURL: rootURL,
        )
        let source = InspectorConfiguration.SwiftDataSource(
            id: .init(rawValue: "broken"),
            title: "Broken Store",
            storageRootURL: rootURL,
            storeURL: storeURL,
            recoveryStorageURLs: [recoveryURL],
            makeContainer: { throw IncompatibleStoreError() },
        )
        let model = InspectorModel(configuration: InspectorConfiguration(
            title: "Inspector",
            fileContainers: [container],
            defaultsDomains: [],
            swiftDataSources: [source],
        ), modeController: modeFixture.controller)
        await model.prepare()

        #expect(model.canEraseUnreadableStore(id: source.id))
        let protectedFileSystem = try #require(model.fileSystem)
        let protectedItems = try await protectedFileSystem.contents(of: rootURL, in: container)
        #expect(
            protectedItems.first(where: { $0.url == similarlyNamedURL })?
                .deletionProhibition != nil,
        )

        #expect(await model.eraseUnreadableStore(id: source.id))
        #expect(model.swiftDataFailures[source.id] == nil)
        #expect(model.loadedSwiftDataSources[source.id] == nil)
        #expect(model.visibleSwiftDataSources.isEmpty)
        #expect(model.removedSwiftDataSourceIDs == [source.id])
        let refreshedFileSystem = try #require(model.fileSystem)
        let refreshedItems = try await refreshedFileSystem.contents(of: rootURL, in: container)
        #expect(
            refreshedItems.first(where: { $0.url == similarlyNamedURL })?
                .deletionProhibition == nil,
        )
        #expect(
            FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)) == false,
        )
        #expect(
            FileManager.default.fileExists(atPath: walURL.path(percentEncoded: false)) == false,
        )
        #expect(
            FileManager.default.fileExists(
                atPath: recoveryURL.path(percentEncoded: false),
            ) == false,
        )
        #expect(
            FileManager.default.fileExists(
                atPath: similarlyNamedURL.path(percentEncoded: false),
            ),
        )

        let lateSidecarURL = rootURL.appending(path: "broken.store-shm")
        try Data("late checkpoint".utf8).write(to: lateSidecarURL)
        try FileManager.default.createDirectory(
            at: recoveryURL,
            withIntermediateDirectories: true,
        )
        try Data("late journal".utf8).write(to: recoveryURL.appending(path: "segment"))
        let nextProcessController = InspectorModeController(
            userDefaults: modeFixture.defaults,
        )
        #expect(nextProcessController.completePendingStoreErasures(fileManager: .default))
        #expect(
            FileManager.default.fileExists(
                atPath: lateSidecarURL.path(percentEncoded: false),
            ) == false,
        )
        #expect(
            FileManager.default.fileExists(
                atPath: recoveryURL.path(percentEncoded: false),
            ) == false,
        )
    }

    @Test func unreadableSourceWithoutAnExactStoreURLCannotBeErased() async throws {
        let modeFixture = try InspectorModeControllerFixture()
        defer { modeFixture.cleanup() }
        let source = InspectorConfiguration.SwiftDataSource(
            id: .init(rawValue: "unconfigured"),
            title: "Unconfigured Store",
            storageRootURL: FileManager.default.temporaryDirectory,
            makeContainer: { throw IncompatibleStoreError() },
        )
        let model = InspectorModel(configuration: InspectorConfiguration(
            title: "Inspector",
            fileContainers: [],
            defaultsDomains: [],
            swiftDataSources: [source],
        ), modeController: modeFixture.controller)
        await model.prepare()

        #expect(model.canEraseUnreadableStore(id: source.id) == false)
        #expect(await model.eraseUnreadableStore(id: source.id) == false)
        #expect(model.swiftDataFailures[source.id] != nil)
    }

    @Test func loadedSourceProtectsItsConfiguredRecoveryStorage() async throws {
        let modeFixture = try InspectorModeControllerFixture()
        defer { modeFixture.cleanup() }
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-model-protection-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        let recoveryURL = rootURL.appending(
            path: "Periscope-Journals",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(
            at: recoveryURL,
            withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let container = InspectorConfiguration.FileContainer(
            id: .init(rawValue: "storage"),
            title: "Storage",
            rootURL: rootURL,
        )
        let source = InspectorConfiguration.SwiftDataSource(
            id: .init(rawValue: "loaded"),
            title: "Loaded Store",
            storageRootURL: rootURL,
            storeURL: rootURL.appending(path: "Periscope.store"),
            recoveryStorageURLs: [recoveryURL],
            modelTypes: [TestWidget.self],
            makeContainer: {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(
                    for: TestWidget.self,
                    configurations: configuration,
                )
            },
        )
        let model = InspectorModel(configuration: InspectorConfiguration(
            title: "Inspector",
            fileContainers: [container],
            defaultsDomains: [],
            swiftDataSources: [source],
        ), modeController: modeFixture.controller)

        await model.prepare()

        let fileSystem = try #require(model.fileSystem)
        let items = try await fileSystem.contents(of: rootURL, in: container)
        #expect(
            items.first(where: { $0.url == recoveryURL })?
                .deletionProhibition != nil,
        )
    }

    @Test func invalidEraseConfigurationKeepsTheSourceVisible() async throws {
        let modeFixture = try InspectorModeControllerFixture()
        defer { modeFixture.cleanup() }
        let storageRootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-model-root-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        let outsideRootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-model-outside-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(
            at: storageRootURL,
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: outsideRootURL,
            withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: storageRootURL) }
        defer { try? FileManager.default.removeItem(at: outsideRootURL) }
        let storeURL = outsideRootURL.appending(path: "broken.store")
        try Data("broken".utf8).write(to: storeURL)
        let source = InspectorConfiguration.SwiftDataSource(
            id: .init(rawValue: "broken"),
            title: "Broken Store",
            storageRootURL: storageRootURL,
            storeURL: storeURL,
            makeContainer: { throw IncompatibleStoreError() },
        )
        let model = InspectorModel(configuration: InspectorConfiguration(
            title: "Inspector",
            fileContainers: [],
            defaultsDomains: [],
            swiftDataSources: [source],
        ), modeController: modeFixture.controller)
        await model.prepare()

        #expect(await model.eraseUnreadableStore(id: source.id) == false)
        #expect(
            FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)),
        )
        #expect(model.visibleSwiftDataSources.map(\.id) == [source.id])
        #expect(model.removedSwiftDataSourceIDs.isEmpty)
        #expect(model.swiftDataFailures[source.id]?.contains("outside") == true)
    }
}

private struct IncompatibleStoreError: LocalizedError {
    var errorDescription: String? {
        "The store schema is incompatible."
    }
}
