@testable import Flagger
import Testing

struct FeatureFlagBehaviorTests {
    @Test
    func markerTypesExposeTheirResolutionKinds() {
        #expect(ReadOnceOnLaunch.kind == .readOnceOnLaunch)
        #expect(ReadOnceOnFirstAccess.kind == .readOnceOnFirstAccess)
        #expect(LiveUpdating.kind == .liveUpdating)
    }
}
