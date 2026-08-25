import Foundation
import Testing
@_spi(Testing) @testable import ThrowUI

@MainActor
struct OnboardingFlowModelTests {
    @Test func calibrationDemandSynchronizesDraftAndRequiresChosenOutput() {
        let session = ThrowSession.fixture()
        let outputs = ControllerProjectionOutputs()
        let model = OnboardingFlowModel(session: session, outputs: outputs)
        model.step = .calibration
        model.calibrationOutputChoice = .fullScreenPreview

        model.beginCalibration()
        model.screenTopBearing = 123
        model.safeInsetPercent = 12

        #expect(session.isCalibrating)
        #expect(session.screenTopBearing == 123)
        #expect(session.safeInsetPercent == 12)
        #expect(model.canContinue == false)

        model.markFullScreenPreviewPresented()
        #expect(model.canContinue)

        model.endCalibration()
        #expect(session.isCalibrating == false)
    }

    @Test func equalQuietEndpointsBlockAppearanceStep() {
        let session = ThrowSession.fixture()
        let model = OnboardingFlowModel(
            session: session,
            outputs: ControllerProjectionOutputs(),
        )
        model.step = .appearance
        model.quietEnabled = true
        model.quietEnd = model.quietStart

        #expect(model.quietScheduleIsValid == false)
        #expect(model.canContinue == false)

        model.quietEnd = model.quietStart.addingTimeInterval(60)
        #expect(model.quietScheduleIsValid)
        #expect(model.canContinue)
    }
}
