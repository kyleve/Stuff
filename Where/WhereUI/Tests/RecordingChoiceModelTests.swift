import Foundation
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct RecordingChoiceModelTests {
    @Test func openingReviewDoesNotSelectOrWriteAndAnExplicitChoicePreservesRawEvidence(
    ) async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingChoiceModel(services: fixture.services, periods: fixture.periods)
        let original = try await fixture.store.allSamples()
        await model.load()
        #expect(!model.canApply)
        #expect(try await fixture.controls().sourceChoices.isEmpty)
        #expect(model.deviceNames[RecordingReviewTestSupport.first] == "Phone One")
        await model.apply()
        #expect(try await fixture.controls().sourceChoices.isEmpty)
        await model.review(.init(
            scope: .periods(fixture.periods),
            action: .select(RecordingReviewTestSupport.first),
        ))
        let preview = try RecordingReviewTestSupport.preview(model)
        #expect(preview.before.issues.count == 1)
        #expect(preview.after.issues.isEmpty)
        #expect(preview.after.contributions.first?.regions == [.california])
        #expect(model.canApply)
        await model.apply()
        #expect(model.didApply)
        #expect(try await fixture.controls().sourceChoices
            .map(\.id) == [preview.proposal.decision.id])
        #expect(try await Set(fixture.store.allSamples()) == Set(original))
    }

    @Test func changedEvidenceRequiresASecondExplicitApply() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingChoiceModel(services: fixture.services, periods: fixture.periods)
        await model.review(.init(
            scope: .periods(fixture.periods),
            action: .select(RecordingReviewTestSupport.first),
        ))
        let first = try RecordingReviewTestSupport.preview(model)
        try await fixture.add([RecordingReviewTestSupport.sample(
            deviceID: RecordingReviewTestSupport.second,
            seconds: 900,
        )])
        await model.apply()
        guard case .ready(.reviewed(_, _, refreshed: true)) = model.state else {
            Issue.record("Changed inputs must be shown before another Save")
            return
        }
        let updated = try RecordingReviewTestSupport.preview(model)
        #expect(updated.proposal.decision.id != first.proposal.decision.id)
        #expect(updated.proposal.decision.periods == first.proposal.decision.periods)
        #expect(try await fixture.controls().sourceChoices.isEmpty)
        await model.apply()
        #expect(model.didApply)
        #expect(try await fixture.controls().sourceChoices
            .map(\.id) == [updated.proposal.decision.id])
    }

    @Test func explicitAutomaticChoiceKeepsDisjointPeriodsAndDoesNotSelectTheGap() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let periods = try [
            RecordingPeriod(
                start: RecordingReviewTestSupport.date(0),
                end: RecordingReviewTestSupport.date(100),
            ),
            RecordingPeriod(
                start: RecordingReviewTestSupport.date(1100),
                end: RecordingReviewTestSupport.date(1201),
            ),
        ]
        let model = RecordingChoiceModel(services: fixture.services, periods: periods)
        await model.load()
        #expect(!model.canApply)
        await model.review(.init(scope: .periods(periods), action: .automatic))
        #expect(model.canApply)
        let preview = try RecordingReviewTestSupport.preview(model)
        #expect(preview.proposal.decision.periods == periods)
        #expect(preview.proposal.decision.action == .automatic)
        await model.apply()
        #expect(model.didApply)
        #expect(try await fixture.controls().sourceChoices.first?.periods == periods)
    }

    @Test func wholeDayNeedsContextWhileAnExactPeriodStillShowsUnknownDates() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let model = RecordingChoiceModel(services: fixture.services, periods: fixture.periods)
        await model.review(.init(
            scope: .recordingDay(
                deviceID: RecordingReviewTestSupport.first,
                day: RecordingReviewTestSupport.day,
            ),
            action: .select(RecordingReviewTestSupport.first),
        ))
        guard case .needsCalendarContext = model.inspection else {
            Issue.record("A whole day cannot guess its calendar coverage")
            return
        }
        #expect(!model.canApply)
        await model.review(.init(
            scope: .periods(fixture.periods),
            action: .select(RecordingReviewTestSupport.first),
        ))
        let preview = try RecordingReviewTestSupport.preview(model)
        #expect(preview.after.contributions.isEmpty)
        #expect(preview.after.issues.first?.days == .unassigned(known: []))
        #expect(model.canApply)
    }

    @Test func supersededInspectionCannotReplaceTheLatestExplicitChoice() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingChoiceModel(services: fixture.services, periods: fixture.periods)
        let hold = ResolutionScanSuspension()
        model.setBeforePublicationForTesting { await hold.suspendFirst() }
        let older = Task { await model.load() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        await model.review(.init(
            scope: .periods(fixture.periods),
            action: .select(RecordingReviewTestSupport.second),
        ))
        let current = try RecordingReviewTestSupport.preview(model).proposal
        hold.resume()
        await older.value
        #expect(try RecordingReviewTestSupport.preview(model).proposal == current)
        #expect(model.canApply)
    }

    @Test(arguments: [false, true])
    func interruptionDiscardsHeldInspection(revoke: Bool) async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingChoiceModel(services: fixture.services, periods: fixture.periods)
        let hold = ResolutionScanSuspension()
        model.setBeforePublicationForTesting { await hold.suspendFirst() }
        let pending = Task { await model.load() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        if revoke { await fixture.services.retireCompatibilityScope() } else { pending.cancel() }
        hold.resume()
        await pending.value
        #expect(model.inspection == nil)
        #expect(!model.canApply)
        if revoke {
            guard case .failed = model.state else {
                Issue.record("Revocation must expose a failure")
                return
            }
        }
    }

    @Test func closingDuringSaveDoesNotPublishSuccessAfterTheCommit() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingChoiceModel(services: fixture.services, periods: fixture.periods)
        await model.review(.init(
            scope: .periods(fixture.periods),
            action: .select(RecordingReviewTestSupport.first),
        ))
        let proposal = try RecordingReviewTestSupport.preview(model).proposal
        let hold = ResolutionScanSuspension()
        model.setBeforePublicationForTesting { await hold.suspendFirst() }
        let pending = Task { await model.apply() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        model.deactivate()
        hold.resume()
        await pending.value
        #expect(!model.didApply)
        #expect(model.inspection == nil)
        #expect(try await fixture.controls().sourceChoices.map(\.id) == [proposal.decision.id])
    }

    @Test func failedScopeEditRetainsOriginalErrorWithoutEnablingTheOldProposal() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingChoiceModel(services: fixture.services, periods: fixture.periods)
        await model.load()
        let original = model.inspection
        await model.review(.init(scope: .periods([]), action: .automatic))
        guard case let .failed(error, _) = model.state else {
            Issue.record("An empty scope must fail")
            return
        }
        #expect(error as? DataCompatibilityError == .incompleteRecord)
        #expect(model.inspection == original)
        #expect(!model.canApply)
        await model.retry()
        #expect(!model.canApply)
        #expect(try await fixture.controls().sourceChoices.isEmpty)
    }

    @Test(arguments: [false, true])
    func failedSaveRetryPreservesTheProposalAndRequiresAnActiveRequest(revoke: Bool) async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingChoiceModel(services: fixture.services, periods: fixture.periods)
        await model.review(.init(
            scope: .periods(fixture.periods),
            action: .select(RecordingReviewTestSupport.first),
        ))
        let proposal = try RecordingReviewTestSupport.preview(model).proposal
        // Lose completion after the real durable save. A retry must keep its operation identity.
        model.setBeforePublicationForTesting {
            throw RecordingReviewTestSupport.TestFailure.interruptedSaveReceipt
        }
        await model.apply()
        guard case let .failed(error, .save) = model.state else {
            Issue.record("The interrupted receipt must retain save recovery")
            return
        }
        #expect(error as? RecordingReviewTestSupport.TestFailure == .interruptedSaveReceipt)
        model.setBeforePublicationForTesting {}

        // Main-actor isolation prevents the task from entering retry before cancellation.
        let cancelled = Task { await model.retry() }
        cancelled.cancel()
        await cancelled.value
        guard case let .failed(error, .save) = model.state else {
            Issue.record("An already-cancelled retry must not revive Apply or erase the failure")
            return
        }
        #expect(error as? RecordingReviewTestSupport.TestFailure == .interruptedSaveReceipt)
        #expect(!model.canApply)
        #expect(!model.didApply)

        if revoke { await fixture.services.retireCompatibilityScope() }
        await model.retry()
        if revoke {
            guard case .failed(_, .load) = model.state else {
                Issue.record("Retired access must discard the retained save proposal")
                return
            }
            #expect(model.inspection == nil)
            #expect(!model.canApply)
            #expect(!model.didApply)
        } else {
            #expect(model.didApply)
        }
        #expect(try await fixture.controls().sourceChoices.map(\.id) == [proposal.decision.id])
    }
}
