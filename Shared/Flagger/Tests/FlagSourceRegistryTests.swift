@testable import Flagger
import Testing

struct FlagSourceRegistryTests {
    @Test
    func builderRegistersSourceMetadataAndGroups() {
        let registration = testSources.registrations.first

        #expect(registration?.metadata.id == TestFlagSource.id)
        #expect(registration?.groups.registrations.count == 1)
    }
}
