import Testing
@testable import WhereUI

@MainActor
struct PassportCardSurfaceKindTests {
    @Test func surfaceIdentityDoesNotDependOnMotionAvailability() {
        let tilt = TiltProvider.preview

        #expect(PassportCardSurfaceKind.securityPrint.tilt == nil)
        #expect(PassportCardSurfaceKind.securityPrint.isReflective == false)
        #expect(PassportCardSurfaceKind.reflective(tilt: tilt).tilt === tilt)
        #expect(PassportCardSurfaceKind.reflective(tilt: tilt).isReflective)
    }
}
