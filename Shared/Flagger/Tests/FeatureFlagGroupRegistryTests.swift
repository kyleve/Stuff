@testable import Flagger
import Testing

struct FeatureFlagGroupRegistryTests {
    @Test
    func builderRegistersConcreteGroupMetadataAndFactory() {
        let type = TestFlagSource.groups.types.first

        #expect(type?.id == TestFlags.id)
        #expect(type?.name == TestFlags.name)
        #expect(type?.init() is TestFlags)
    }
}
