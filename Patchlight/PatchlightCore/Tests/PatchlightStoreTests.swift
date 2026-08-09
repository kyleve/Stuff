import Foundation
import PatchlightCore
import Testing

struct PatchlightStoreTests {
    @Test func v1ContainerOpensInMemoryAndExposesEveryInspectorModel() throws {
        _ = try PatchlightStore.make(storage: .inMemory)
        #expect(PatchlightStore.inspectorModelTypes.count == 8)
    }

    @Test func v1OnDiskContainerReopensThroughTheMigrationPlan() throws {
        let directory = try PatchlightCoreTestSupport.temporaryDirectory(#function)
        let url = directory.appendingPathComponent("Patchlight.store")
        _ = try PatchlightStore.make(storage: .onDisk(url))
        _ = try PatchlightStore.make(storage: .onDisk(url))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
