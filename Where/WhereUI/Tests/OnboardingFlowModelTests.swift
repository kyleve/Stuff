import Foundation
import LifecycleKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct OnboardingFlowModelTests {
    @Test func waitingPreservesTheSelectedArchiveAndDoesNotAuthorizeIt() {
        let model = makeModel(startsAtRecordingChoice: true)
        let url = URL(fileURLWithPath: "/tmp/compatibility-review.zip")
        model.handleRestoreSelection(.success(url))
        model.chooseRestoreStrategy(.replace)
        model.compatibilityReview = .preview
        model.waitForDeviceUpdates()
        #expect(model.compatibilityReview == nil)
        #expect(model.restoreSelection.readyImport?.url == url)
        #expect(model.restoreSelection.readyImport?.strategy == .replace)
        #expect(!model.isFinishing)
        #expect(model.phase == .location)
    }

    @Test func startsAtTheRequestedPhaseAndUsesTheHardwareRecommendation() {
        let model = makeModel(startsAtRecordingChoice: true)

        #expect(model.phase == .location)
        #expect(model.recordingEnabled)
    }

    @Test func finalIntroPageAdvancesToThemeSelection() {
        let model = makeModel(startsAtRecordingChoice: false)
        model.page = OnboardingPage.all.count - 1

        model.advanceIntro(pageCount: OnboardingPage.all.count)

        #expect(model.phase == .theme)
    }

    @Test func normalThemeSelectionContinuesToRegionSelection() {
        let model = makeModel(startsAtRecordingChoice: false)

        model.continueAfterThemeSelection()

        #expect(model.phase == .pickRegions)
    }

    @Test func restoredThemeSelectionContinuesToRecordingConfirmation() {
        let model = makeModel(startsAtRecordingChoice: false)
        model.handleRestoreSelection(.success(URL(fileURLWithPath: "/tmp/where-theme-test.zip")))
        model.chooseRestoreStrategy(.merge)

        #expect(model.phase == .theme)
        model.continueAfterThemeSelection()

        #expect(model.phase == .location)
    }

    private func makeModel(startsAtRecordingChoice: Bool) -> OnboardingFlowModel {
        OnboardingFlowModel(
            gate: LifecycleGateHandle(
                id: LaunchStepID.onboarding,
                reason: .userForeground,
            ),
            installationContext: .testing,
            startsAtRecordingChoice: startsAtRecordingChoice,
            initialTheme: .standard,
        )
    }
}
