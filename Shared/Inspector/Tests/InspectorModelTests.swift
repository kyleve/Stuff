import Foundation
@testable import Inspector
import Testing

@MainActor
struct InspectorModelTests {
    @Test func failedSwiftDataSourceRemainsConfiguredWithDegradedState() async {
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
        ))

        await model.prepare()

        #expect(model.preparationState == .ready)
        #expect(model.configuration.swiftDataSources.map(\.id) == [source.id])
        #expect(model.visibleSwiftDataSources.map(\.id) == [source.id])
        #expect(model.loadedSwiftDataSources[source.id] == nil)
        #expect(model.swiftDataFailures[source.id]?.isEmpty == false)
        #expect(model.fileSystem != nil)
    }

    @Test func erasesAnUnreadableStoreFamilyAndRemovesTheSource() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-model-erase-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let storeURL = rootURL.appending(path: "broken.store")
        let walURL = rootURL.appending(path: "broken.store-wal")
        let similarlyNamedURL = rootURL.appending(path: "broken.store-backup")
        try Data("broken".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: walURL)
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
            makeContainer: { throw IncompatibleStoreError() },
        )
        let model = InspectorModel(configuration: InspectorConfiguration(
            title: "Inspector",
            fileContainers: [container],
            defaultsDomains: [],
            swiftDataSources: [source],
        ))
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
                atPath: similarlyNamedURL.path(percentEncoded: false),
            ),
        )
    }

    @Test func unreadableSourceWithoutAnExactStoreURLCannotBeErased() async {
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
        ))
        await model.prepare()

        #expect(model.canEraseUnreadableStore(id: source.id) == false)
        #expect(await model.eraseUnreadableStore(id: source.id) == false)
        #expect(model.swiftDataFailures[source.id] != nil)
    }

    @Test func invalidEraseConfigurationKeepsTheSourceVisible() async throws {
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
        ))
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
