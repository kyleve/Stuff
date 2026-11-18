@testable import Flagger
import Testing

struct FlagSourceTests {
    @Test
    func metadataKeepsTypedSourceIdentity() {
        let metadata = FeatureFlagSourceMetadata(id: TestFlagSource.id, name: TestFlagSource.name)

        #expect(metadata.id == TestFlagSource.id)
        #expect(metadata.name == TestFlagSource.name)
    }
}
