import Foundation
import LifecycleKit
import Testing
@_spi(Testing) @testable import WhereCore
@testable import WhereUI

struct WhereLifecycleFailureViewTests {
    private static let summary = BackupCoordinator.ImportSummary(
        sampleCount: 3,
        evidenceCount: 2,
        manualDayCount: 5,
        dismissedIssueCount: 4,
        trackedRegionCount: 6,
        recordingDeviceCount: 2,
        recordingAssignmentChangeCount: 7,
    )

    @Test func committedImportCleanupPreservesSummaryInADedicatedPresentation() throws {
        let failure = LifecycleFailure(
            stepID: "onboarding",
            error: BackupCoordinator.CommittedImportCleanupError(
                strategy: .replace,
                summary: Self.summary,
                underlying: TestFailure(),
            ),
        )

        let presentation = try #require(WhereLifecycleFailurePresentation(failure: failure))

        #expect(presentation == .committedImportCleanup(Self.summary))
        #expect(presentation.title == "Backup imported; cleanup incomplete")
        #expect(presentation.message.contains("Imported 3 location samples"))
        #expect(presentation.message.contains("Do not import this backup again."))
    }

    @Test func committedResetCleanupUsesDedicatedCommittedResetCopy() throws {
        let failure = LifecycleFailure(
            stepID: "erase-data",
            error: WhereServices.ResetCleanupError(underlying: TestFailure()),
        )

        let presentation = try #require(WhereLifecycleFailurePresentation(failure: failure))

        #expect(presentation == .committedResetCleanup)
        #expect(presentation.title == "Data erased; cleanup incomplete")
        #expect(presentation.message.contains("Your synced data was erased"))
        #expect(presentation.message.contains("Close and reopen Where"))
    }

    @Test func committedOnboardingImportSetupFailurePreservesTheBoundary() throws {
        let failure = LifecycleFailure(
            stepID: "onboarding",
            error: OnboardingCommittedImportSetupError(
                summary: Self.summary,
                underlying: TestFailure(),
            ),
        )

        let presentation = try #require(WhereLifecycleFailurePresentation(failure: failure))

        #expect(presentation == .committedImportSetup(Self.summary))
        #expect(presentation.title == "Backup imported; setup incomplete")
        #expect(presentation.message.contains("Imported 3 location samples"))
        #expect(presentation.message.contains("setup will retry automatically"))
        #expect(presentation.message.contains("Do not import this backup again."))
    }

    @Test func ordinaryLaunchFailureUsesLifecycleKitsGenericPresentation() {
        let failure = LifecycleFailure(stepID: "open-store", error: TestFailure())

        #expect(WhereLifecycleFailurePresentation(failure: failure) == nil)
    }
}

private struct TestFailure: LocalizedError {
    var errorDescription: String? {
        "Test failure"
    }
}
