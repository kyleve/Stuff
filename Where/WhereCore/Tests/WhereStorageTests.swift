import Foundation
import SwiftData
import Testing
@testable import WhereCore

struct WhereStorageTests {
    @Test func opensTheExistingStoreWithoutMovingItOrItsNeighbors() async throws {
        let group = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let storeURL = group.appending(path: "Library/Application Support/default.store")
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: group) }
        let widgetURL = group.appending(path: "widget-snapshot.json")
        let widgetBytes = Data("existing widget snapshot".utf8)
        try widgetBytes.write(to: widgetURL)
        try seedExistingStore(at: storeURL)

        let opened = try await WhereStorage.makeContainer(groupContainerURL: group, cloudKit: .none)
        #expect(opened.configurations.first?.url.standardizedFileURL == storeURL
            .standardizedFileURL)
        #expect(SwiftDataStore.inspectorStoreURL(groupContainerURL: group) == storeURL)
        let context = ModelContext(opened)
        #expect(try context.fetch(FetchDescriptor<SDTrackedRegion>()).map(\.regionID) == ["us-CA"])
        #expect(try Data(contentsOf: widgetURL) == widgetBytes)
        #expect(!FileManager.default.fileExists(atPath: group.appending(path: "Where").path))
    }

    @Test func missingAppGroupThrowsInsteadOfOpeningASandboxStore() async {
        await #expect(throws: WhereStorage.AppGroupUnavailableError.self) {
            try await SwiftDataStore.makeContainer(storage: .localOnly(
                appGroupIdentifier: "group.storagekit.tests.unavailable.\(UUID().uuidString)",
            ))
        }
    }

    private func seedExistingStore(at url: URL) throws {
        let schema = Schema(SwiftDataStore.inspectorModelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(
            schema: schema,
            url: url,
            cloudKitDatabase: .none,
        )])
        let context = ModelContext(container)
        context.insert(SDTrackedRegion(regionID: "us-CA", generationID: .initial))
        try context.save()
    }
}
