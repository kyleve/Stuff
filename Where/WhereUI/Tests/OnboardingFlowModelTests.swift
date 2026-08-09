import Foundation
import LifecycleKit
import RegionKit
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

    @Test func approvedPhotoDraftWaitsForTheFinalRecordingChoice() throws {
        let model = makeModel(startsAtRecordingChoice: false)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let draft = PhotoHistoryDraft(
            year: 2026,
            calendar: calendar,
            samples: [LocationSample(
                timestamp: Date(timeIntervalSince1970: 1_768_500_000),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 12,
                source: .photo,
            )],
            regions: [.california],
        )
        model.photoImport.activity = .ready(draft, isLimited: false)

        model.approvePhotoHistory()

        #expect(model.phase == .location)
        guard case .importing = model.photoImport.activity else {
            Issue.record("The approved draft should remain pending until final confirmation")
            return
        }
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
