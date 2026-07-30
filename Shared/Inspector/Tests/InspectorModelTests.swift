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
        #expect(model.loadedSwiftDataSources[source.id] == nil)
        #expect(model.swiftDataFailures[source.id]?.isEmpty == false)
        #expect(model.fileSystem != nil)
    }
}

private struct IncompatibleStoreError: LocalizedError {
    var errorDescription: String? {
        "The store schema is incompatible."
    }
}
