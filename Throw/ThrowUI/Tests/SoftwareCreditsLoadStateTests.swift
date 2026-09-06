import Testing
@testable import ThrowUI

struct SoftwareCreditsLoadStateTests {
    @Test func loadedEmptyReportIsNotFailure() {
        let state = SoftwareCreditsLoadState.loaded([])

        #expect(state != .failed)
    }
}
