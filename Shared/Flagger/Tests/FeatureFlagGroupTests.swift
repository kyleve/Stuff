@testable import Flagger
import Testing

struct FeatureFlagGroupTests {
    @Test
    func namespaceConstructsTheRequestedConcreteGroup() {
        let group = FeatureFlagGroups()[TestFlags.self]

        #expect(group.liveBoolean.id == TestFlags().liveBoolean.id)
        #expect(TestFlags.detail == nil)
    }
}
