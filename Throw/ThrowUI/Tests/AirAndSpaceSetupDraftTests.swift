import Testing
import ThrowCore
@testable import ThrowUI

struct AirAndSpaceSetupDraftTests {
    @Test func defaultsMatchNewAirAndSpaceConfiguration() {
        let draft = AirAndSpaceSetupDraft()

        #expect(draft.sourceChoice == nil)
        #expect(draft.sourceValidation == .untested)
        #expect(draft.validatedSource == nil)
        #expect(draft.selectedMode == nil)
        #expect(draft.mapRadius == MapViewport.defaultValue.radius.value)
        #expect(draft.minimumElevation == SkyViewport.defaultValue.minimumElevation.degrees)
    }
}
