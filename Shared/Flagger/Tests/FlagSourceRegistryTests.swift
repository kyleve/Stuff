@testable import Flagger
import Testing

struct FlagSourceRegistryTests {
    @Test
    func builderRegistersSourceMetadataAndGroups() {
        let type = testSources.types.first

        #expect(type?.id == TestFlagSource.id)
        #expect(type?.groups.types.count == 1)
    }
}
