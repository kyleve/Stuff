import Foundation
import Testing
import WhereCore
@testable import WhereUI

struct OnboardingRestoreSelectionTests {
    @Test func requiresAnExplicitStrategyAndRecommendsMerge() {
        var selection = OnboardingRestoreSelection(
            url: URL(fileURLWithPath: "/tmp/where-backup.zip"),
            hasScopedAccess: false,
        )

        #expect(selection.strategy == nil)
        #expect(OnboardingRestoreSelection.recommendedStrategy == .merge)

        selection.choose(.merge)

        #expect(selection.strategy == .merge)
    }

    @Test func preservesAnExplicitReplaceChoice() {
        var selection = OnboardingRestoreSelection(
            url: URL(fileURLWithPath: "/tmp/where-backup.zip"),
            hasScopedAccess: false,
        )

        selection.choose(.replace)

        #expect(selection.strategy == .replace)
    }

    @Test func committedImportRetainsItsBoundaryAndCannotReturnToSelection() throws {
        var selection = OnboardingRestoreSelection(
            url: URL(fileURLWithPath: "/tmp/where-backup.zip"),
            hasScopedAccess: false,
        )
        selection.choose(.merge)
        let ready = try #require(selection.readyImport)

        selection.markCommitted(Self.summary)
        selection.discardUncommittedSelection()

        #expect(ready.url.lastPathComponent == "where-backup.zip")
        #expect(ready.strategy == .merge)
        #expect(selection.selectedURL == nil)
        #expect(selection.strategy == nil)
        #expect(selection.readyImport == nil)
        #expect(selection.committedSummary == Self.summary)
    }

    private static let summary = BackupCoordinator.ImportSummary(
        sampleCount: 3,
        evidenceCount: 2,
        manualDayCount: 1,
        dismissedIssueCount: 4,
        trackedRegionCount: 5,
        recordingDeviceCount: 2,
        recordingPolicyChangeCount: 3,
    )
}
