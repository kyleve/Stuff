import Foundation
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct OnboardingImportRecoveryModelTests {
    @Test(arguments: [false, true])
    func supersededAdmissionDoesNotBecomeAnImportFailure(cancelled: Bool) async throws {
        let installation = InMemoryInstallationRecordingContextStore(context: .testing)
        try installation.setBackupImportRecovery(.prepared(.init(
            transactionID: UUID(),
            strategy: .merge,
            summary: .init(
                sampleCount: 0,
                evidenceCount: 0,
                manualDayCount: 0,
                dismissedIssueCount: 0,
                trackedRegionCount: 0,
                recordingDeviceCount: 0,
                recordingDeviceRemovalCount: 0,
            ),
        )))
        let model = OnboardingImportRecoveryModel(installationContextStore: installation)
        _ = await model.recoverInterruptedImport(
            requiresOnboarding: false,
            resolveScope: {
                if cancelled { throw CancellationError() }
                throw DataCompatibilityFailure.updateRequired(.init(rawValue: 2))
            },
            endSession: { Issue.record("Admission failure must not abandon import recovery") },
            completeOnboarding: { Issue.record("Admission failure must not complete onboarding") },
        )
        #expect(model.takeInterruptedImportError() == nil)
        #expect(installation.backupImportRecovery != nil)
    }

    @Test func noMarkerPreservesTheOrdinaryOnboardingDecision() async {
        let model = OnboardingImportRecoveryModel(
            installationContextStore: InMemoryInstallationRecordingContextStore(
                context: .testing,
            ),
        )
        var resolvedScope = false

        let needsOnboarding = await model.recoverInterruptedImport(
            requiresOnboarding: true,
            resolveScope: {
                resolvedScope = true
                throw UnexpectedScopeResolution()
            },
            endSession: {},
            completeOnboarding: {},
        )

        #expect(needsOnboarding)
        #expect(!resolvedScope)
        #expect(model.takeInterruptedImportError() == nil)
    }
}

private struct UnexpectedScopeResolution: Error {}
