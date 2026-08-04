@testable import Flagger
import Testing

struct FeatureFlagGroupRegistryTests {
    @Test
    func builderRegistersConcreteGroupMetadataAndFactory() {
        let registration = TestFlagSource.groups.registrations.first

        #expect(registration?.metadata.id == TestFlags.id)
        #expect(registration?.metadata.name == TestFlags.name)
        #expect(registration?.make() is TestFlags)
    }
}
