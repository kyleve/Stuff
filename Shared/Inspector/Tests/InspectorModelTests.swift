import Foundation
@testable import Inspector
import SwiftData
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
        #expect(model.loadedSwiftDataSources[source.id] == nil)
        #expect(model.swiftDataFailures[source.id]?.isEmpty == false)
        #expect(model.fileSystem != nil)
    }

    @Test func erasesAnUnreadableStoreFamilyAndReopensTheSource() async throws {
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
        let source = InspectorConfiguration.SwiftDataSource(
            id: .init(rawValue: "broken"),
            title: "Broken Store",
            storageRootURL: rootURL,
            storeURL: storeURL,
            makeContainer: {
                if FileManager.default.fileExists(
                    atPath: storeURL.path(percentEncoded: false),
                ) {
                    throw IncompatibleStoreError()
                }
                return try Self.makeReopenedContainer()
            },
        )
        let model = InspectorModel(configuration: InspectorConfiguration(
            title: "Inspector",
            fileContainers: [],
            defaultsDomains: [],
            swiftDataSources: [source],
        ))
        await model.prepare()

        #expect(model.canEraseUnreadableStore(id: source.id))
        #expect(await model.eraseUnreadableStore(id: source.id))
        #expect(model.swiftDataFailures[source.id] == nil)
        #expect(model.loadedSwiftDataSources[source.id] != nil)
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

    @Test func failedReopenReportsThatTheFilesWereAlreadyDeleted() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-model-reopen-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let storeURL = rootURL.appending(path: "broken.store")
        try Data("broken".utf8).write(to: storeURL)
        let source = InspectorConfiguration.SwiftDataSource(
            id: .init(rawValue: "broken"),
            title: "Broken Store",
            storageRootURL: rootURL,
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
            FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)) == false,
        )
        #expect(model.swiftDataFailures[source.id]?.contains("files were deleted") == true)
    }

    private nonisolated static func makeReopenedContainer() throws -> ModelContainer {
        let schema = Schema([TestWidget.self, TestGadget.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private struct IncompatibleStoreError: LocalizedError {
    var errorDescription: String? {
        "The store schema is incompatible."
    }
}
