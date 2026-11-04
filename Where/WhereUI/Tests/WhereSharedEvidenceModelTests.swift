import Foundation
import LifecycleKit
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct WhereSharedEvidenceModelTests {
    @Test func aScopeOpenedForRestoreDoesNotConsumeDraftsBeforeReplace() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let queue = SharedEvidenceQueueFixture()
        fixture.sharedDrafts = queue
        let model = fixture.makeModel()
        // This is the scope-resolution boundary used by onboarding before its awaited
        // archive preparation and Replace. Foreground verification can run in this window.
        let scope = try await model.resolveScope()
        let archive = try await scope.services.backup.exportBackup(onProgress: { _ in })
        defer {
            do { try FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
            catch { Issue.record(error) }
        }
        let draft = try SharedEvidenceQueueFixture.draft()
        await queue.enqueue(draft)
        let originalGeneration = try await fixture.store.dataGeneration().id
        #expect(model.session == nil)
        await model.refreshDataCompatibilityIfNeeded()
        await model.importPendingSharedEvidenceIfNeeded()
        #expect(await queue.reads == 0)
        #expect(try await fixture.store.allEvidence().isEmpty)

        _ = try await scope.services.backup.importBackup(
            from: archive,
            strategy: .replace,
            onProgress: { _ in },
        )
        try await scope.services.backup.acknowledgeOnboardingImport()
        #expect(try await fixture.store.dataGeneration().id != originalGeneration)
        let runner = WhereLaunch.makeLauncher(model: model, reason: .undetermined)
        await runner.run()
        #expect(runner.phase.isReady)
        #expect(try await fixture.store.allEvidence().map(\.id) == draft.items.map(\.evidence.id))
        #expect(await queue.pendingDraftIDs().isEmpty)
    }

    @Test func firstVerifiedSessionImportsPendingSharesAndForegroundImportsLaterShares(
    ) async throws {
        let fixture = try CompatibilityLaunchFixture()
        let queue = SharedEvidenceQueueFixture()
        fixture.sharedDrafts = queue
        let draft = try SharedEvidenceQueueFixture.draft()
        await queue.enqueue(draft)
        await fixture.transport.setResult(.failure(CompatibilityLaunchTransport.Offline()))
        let model = fixture.makeModel()
        let runner = WhereLaunch.makeLauncher(model: model, reason: .undetermined)
        let drive = Task { await runner.run() }
        try await CompatibilityLaunchFixture.waitUntil {
            runner.phase.gateHandle?.id == AnyHashable(LaunchStepID.compatibility)
        }
        #expect(await queue.reads == 0)
        #expect(try await fixture.store.allEvidence().isEmpty)
        await fixture.transport.setResult(.success(0))
        await model.refreshDataCompatibilityIfNeeded()
        await drive.value
        #expect(runner.phase.isReady)
        #expect(try await fixture.store.allEvidence().map(\.id) == draft.items.map(\.evidence.id))
        #expect(await queue.pendingDraftIDs().isEmpty)
        let next = try SharedEvidenceQueueFixture.draft()
        await queue.enqueue(next)
        await model.refreshDataCompatibilityIfNeeded()
        #expect(try await fixture.store.allEvidence().count == 2)
        #expect(fixture.assemblyCount == 1)
        #expect(model.sharedEvidence.failure == nil)
    }

    @Test func failedAcknowledgementKeepsHistoryUsableAndRetryDoesNotDuplicateTheShare(
    ) async throws {
        let fixture = try CompatibilityLaunchFixture()
        let queue = SharedEvidenceQueueFixture()
        fixture.sharedDrafts = queue
        try await queue.enqueue(SharedEvidenceQueueFixture.draft())
        await queue.failAcknowledgement(true)
        let model = fixture.makeModel()
        let runner = WhereLaunch.makeLauncher(model: model, reason: .undetermined)
        await runner.run()
        #expect(runner.phase.isReady)
        #expect(model.sharedEvidence.failure is SharedEvidenceQueueFixture.AcknowledgementFailure)
        #expect(model.sharedEvidence.isShowingFailure)
        #expect(try await fixture.store.allEvidence().count == 1)
        model.sharedEvidence.isShowingFailure = false
        #expect(!model.sharedEvidence.isShowingFailure)
        await queue.failAcknowledgement(false)
        await model.importPendingSharedEvidenceIfNeeded()
        #expect(model.sharedEvidence.failure == nil)
        #expect(try await fixture.store.allEvidence().count == 1)
        #expect(await queue.pendingDraftIDs().isEmpty)
    }
}
