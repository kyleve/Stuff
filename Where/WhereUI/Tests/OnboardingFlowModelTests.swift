import Foundation
import LifecycleKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct OnboardingFlowModelTests {
    @Test func startsAtTheRequestedPhaseAndUsesTheHardwareRecommendation() {
        let model = makeModel(startsAtRecordingChoice: true)

        #expect(model.phase == .location)
        #expect(model.recordingEnabled)
    }

    @Test func finalIntroPageAdvancesToRegionSelection() {
        let model = makeModel(startsAtRecordingChoice: false)
        model.page = OnboardingPage.all.count - 1

        model.advanceIntro(pageCount: OnboardingPage.all.count)

        #expect(model.phase == .pickRegions)
    }

    private func makeModel(startsAtRecordingChoice: Bool) -> OnboardingFlowModel {
        OnboardingFlowModel(
            gate: LifecycleGateHandle(
                id: LaunchStepID.onboarding,
                reason: .userForeground,
            ),
            installationContext: .testing,
            startsAtRecordingChoice: startsAtRecordingChoice,
        )
    }
}
