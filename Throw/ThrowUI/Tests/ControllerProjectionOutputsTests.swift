import Testing
@testable import ThrowUI

@MainActor
struct ControllerProjectionOutputsTests {
    @Test func controllerWindowsHaveDistinctOutputIdentities() {
        let first = ControllerProjectionOutputs()
        let second = ControllerProjectionOutputs()

        #expect(first.preview != second.preview)
        #expect(first.fullScreen != second.fullScreen)
        #expect(first.calibration != second.calibration)
    }
}
