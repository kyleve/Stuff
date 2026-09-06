import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct SoftwareCreditsLoadResolutionTests {
    @Test func loadedEmptyReportHasNoDeferredFailure() {
        let resolution = SoftwareCreditsLoadResolution.loaded([])

        #expect(resolution.state == .loaded([]))
        #expect(resolution.failure == nil)
    }

    @Test func failedReportCarriesItsDeferredFailure() {
        let failure = ThrowSoftwareCreditsLoadFailure(
            error: NSError(domain: "com.stuff.throw.attribution-test", code: 42),
        )
        let resolution = SoftwareCreditsLoadResolution.failed(failure)

        #expect(resolution.state == .failed)
        #expect(resolution.failure == failure)
    }
}
