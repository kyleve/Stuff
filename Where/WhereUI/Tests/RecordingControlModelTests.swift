import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct RecordingControlModelTests {
    @Test func aLateObservationReplacesTheReviewBeforeAnotherExplicitSave() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let recovery = try RecordingCalendarRecovery(
            deviceID: RecordingReviewTestSupport.first,
            periods: fixture.periods,
            timeZone: .gmt,
        )
        let model = RecordingControlModel(services: fixture.services)
        await model.review(recovery.edits)
        let original = try #require(model.state.review?.proposal)
        #expect(model.canApply)
        #expect(try await fixture.controls().records.isEmpty)
        try await fixture.add([RecordingReviewTestSupport.sample(
            deviceID: RecordingReviewTestSupport.first,
            seconds: 900,
            unresolved: true,
        )])
        await model.apply()
        guard case let .ready(review) = model.state else {
            Issue.record("Changed evidence must return to review"); return
        }
        #expect(review.refreshed)
        #expect(review.proposal.edits.map(\.control.recordID) !=
            original.edits.map(\.control.recordID))
        #expect(try await fixture.controls().records.isEmpty)
        await model.apply()
        #expect(model.didApply)
        #expect(try await fixture.controls().calendarContexts.count == 1)
    }

    @Test func aLostSaveReceiptRetriesTheOriginalBatchIdentity() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let recovery = try RecordingCalendarRecovery(
            deviceID: RecordingReviewTestSupport.first,
            periods: fixture.periods,
            timeZone: .gmt,
        )
        let model = RecordingControlModel(services: fixture.services)
        await model.review(recovery.edits)
        let proposal = try #require(model.state.review?.proposal)
        model.setBeforePublicationForTesting {
            throw RecordingReviewTestSupport.TestFailure.interruptedSaveReceipt
        }
        await model.apply()
        guard case .failed(_, .save) = model.state else {
            Issue.record("Keep the failed receipt and exact save proposal"); return
        }
        #expect(model.state.review?.proposal == proposal)
        let committed = try await fixture.controls().records
        #expect(committed.count == proposal.edits.count)
        model.setBeforePublicationForTesting {}
        await model.retry()
        #expect(model.didApply)
        #expect(try await fixture.controls().records == committed)
    }

    @Test func cancellingARetryRetainsItsOriginalErrorAndProposal() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let edits = try RecordingCalendarRecovery(
            deviceID: RecordingReviewTestSupport.first,
            periods: fixture.periods,
            timeZone: .gmt,
        ).edits
        let model = RecordingControlModel(services: fixture.services)
        await model.review(edits)
        model.setBeforePublicationForTesting {
            throw RecordingReviewTestSupport.TestFailure.interruptedSaveReceipt
        }
        await model.apply()
        let proposal = try #require(model.state.review?.proposal)
        let hold = ResolutionScanSuspension()
        model.setBeforePublicationForTesting { await hold.suspendFirst() }
        let retry = Task { await model.retry() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        retry.cancel()
        hold.resume()
        await retry.value
        guard case let .failed(error, .save(review)) = model.state else {
            Issue.record("A cancelled retry must preserve its previous failed receipt"); return
        }
        #expect(error as? RecordingReviewTestSupport.TestFailure == .interruptedSaveReceipt)
        #expect(review.proposal == proposal)
        #expect(!model.canApply)
    }

    enum Interruption: CaseIterable { case cancellation, deactivation, revocation }

    @Test(arguments: Interruption.allCases)
    func anInterruptedReviewCannotPublishAWriteProposal(interruption: Interruption) async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let edits = try RecordingCalendarRecovery(
            deviceID: RecordingReviewTestSupport.first,
            periods: fixture.periods,
            timeZone: .gmt,
        ).edits
        let model = RecordingControlModel(services: fixture.services)
        let hold = ResolutionScanSuspension()
        model.setBeforePublicationForTesting { await hold.suspendFirst() }
        let review = Task { await model.review(edits) }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        switch interruption {
            case .cancellation: review.cancel()
            case .deactivation: model.deactivate()
            case .revocation: await fixture.services.retireCompatibilityScope()
        }
        hold.resume()
        await review.value
        #expect(!model.canApply)
        #expect(model.state.review == nil)
        #expect(try await fixture.controls().records.isEmpty)
        if case .revocation = interruption {
            guard case .failed = model.state else {
                Issue.record("Revoked publication must remain an observable failure"); return
            }
        }
    }

    @Test func aSupersededReviewCannotReplaceItsNewerScope() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let model = RecordingControlModel(services: fixture.services)
        let first = try RecordingCalendarRecovery(
            deviceID: RecordingReviewTestSupport.first,
            periods: fixture.periods,
            timeZone: .gmt,
        )
        let second = try RecordingCalendarRecovery(
            deviceID: RecordingReviewTestSupport.second,
            periods: fixture.periods,
            timeZone: .gmt,
        )
        let hold = ResolutionScanSuspension()
        model.setBeforePublicationForTesting { await hold.suspendFirst() }
        let old = Task { await model.review(first.edits) }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        await model.review(second.edits)
        let current = try #require(model.state.review?.proposal)
        hold.resume()
        await old.value
        #expect(model.state.review?.proposal == current)
        #expect(current.edits.map(\.edit) == second.edits)
    }
}
