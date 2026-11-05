import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct RecordingReviewFlowModelTests {
    @Test(arguments: [false, true])
    func cancellationDuringRetryPreservesTheFailureAndSkippedWork(
        reviewRemaining: Bool,
    ) async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try await RecordingReviewFlowModel(
            services: fixture.services,
            references: fixture.references(),
        )
        await model.refresh()
        model.skipCurrent()
        let skipped = try #require(model.state.progress?.skipped)
        try await fixture.store.perform {
            _ = try await fixture.store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: RecordingReviewTestSupport.first,
                at: RecordingReviewTestSupport.date(2000),
            )
        }
        await model.refresh()
        guard case .failed = model.state
        else { Issue.record("Expected generation failure"); return }
        let hold = ResolutionScanSuspension()
        await fixture.services.resolution
            .setBeforeRecordingReviewPublicationForTesting { await hold.suspendFirst() }
        let retry = Task {
            if reviewRemaining { await model.reviewRemaining() } else { await model.refresh() }
        }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        retry.cancel()
        hold.resume()
        await retry.value
        guard case let .failed(error, previous) = model.state
        else { Issue.record("Cancelled reassessment must preserve the prior failure"); return }
        #expect(error as? RecordingReviewQueue.ValidationError == .dataGenerationChanged)
        #expect(previous?.skipped == skipped)
        #expect(!model.canReview)
    }

    @Test func aBufferedChangeCannotRestartADeactivatedObserver() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try await RecordingReviewFlowModel(
            services: fixture.services,
            references: fixture.references(),
        )
        let observer = Task { await model.observeChanges() }
        defer { observer.cancel() }
        try await CompatibilityLaunchFixture.waitUntil { model.page != nil && model.canReview }
        model.deactivate()
        try await fixture.add([RecordingReviewTestSupport.sample(
            deviceID: RecordingReviewTestSupport.second,
            seconds: 900,
        )])
        await observer.value
        guard case .idle = model.state
        else { Issue.record("A late change must not restart closed review"); return }
        #expect(model.page == nil)
    }

    @Test func committedChangesWaitForSavePublicationBeforeAdvancing() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try await RecordingReviewFlowModel(
            services: fixture.services,
            references: fixture.references(),
        )
        let observer = Task { await model.observeChanges() }
        defer { observer.cancel(); model.deactivate() }
        try await CompatibilityLaunchFixture.waitUntil { model.page != nil && model.canReview }
        let page = try #require(model.page)
        await page.choice.load()
        await page.choice.choose(.select(RecordingReviewTestSupport.first))
        let hold = ResolutionScanSuspension()
        page.choice.setBeforePublicationForTesting { await hold.suspendFirst() }
        let save = Task { await page.choice.apply() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered && model.isRefreshing }
        #expect(model.page?.id == page.id)
        #expect(model.state.progress?.remaining.isEmpty == false)
        #expect(try await fixture.controls().sourceChoices.count == 1)
        hold.resume()
        await save.value
        try await CompatibilityLaunchFixture.waitUntil {
            if case .resolved = model.state { return true }
            return false
        }
        #expect(model.page == nil)
    }

    @Test func closingDuringCommittedSaveCannotPublishOrAdvanceTheOldPage() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try await RecordingReviewFlowModel(
            services: fixture.services,
            references: fixture.references(),
        )
        let observer = Task { await model.observeChanges() }
        try await CompatibilityLaunchFixture.waitUntil { model.page != nil && model.canReview }
        let page = try #require(model.page)
        await page.choice.load()
        await page.choice.choose(.select(RecordingReviewTestSupport.first))
        let hold = ResolutionScanSuspension()
        page.choice.setBeforePublicationForTesting { await hold.suspendFirst() }
        let save = Task { await page.choice.apply() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered && model.isRefreshing }
        observer.cancel()
        model.deactivate()
        hold.resume()
        await save.value
        await observer.value
        guard case .idle = model.state
        else { Issue.record("A closed flow must stay retired"); return }
        #expect(model.page == nil)
        #expect(!page.choice.didApply)
        #expect(try await fixture.controls().sourceChoices.count == 1)
    }

    @Test func idempotentSaveRetryReassessesRemainingWorkThroughTheCommitSignal() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let model = try await RecordingReviewFlowModel(
            services: fixture.services,
            references: fixture.references(),
        )
        let observer = Task { await model.observeChanges() }
        defer { observer.cancel(); model.deactivate() }
        try await CompatibilityLaunchFixture.waitUntil { model.page != nil && model.canReview }
        let page = try #require(model.page)
        await page.choice.load()
        await page.choice.choose(.select(RecordingReviewTestSupport.first))
        page.choice
            .setBeforePublicationForTesting {
                throw RecordingReviewTestSupport.TestFailure.interruptedSaveReceipt
            }
        await page.choice.apply()
        try await CompatibilityLaunchFixture.waitUntil { model.canReview }
        guard case .failed = page.choice.state
        else { Issue.record("The saved operation lost its receipt"); return }
        #expect(model.page?.id == page.id)
        page.choice.setBeforePublicationForTesting {}
        await page.choice.retry()
        try await CompatibilityLaunchFixture
            .waitUntil { model.page?.id != page.id && model.canReview }
        #expect(model.state.progress?.remaining.isEmpty == false)
        #expect(try await fixture.controls().sourceChoices.count == 1)
    }

    @Test(arguments: [false, true])
    func cancelledReviewRemainingPreservesSkippedWorkAndFailures(failRefresh: Bool) async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try await RecordingReviewFlowModel(
            services: fixture.services,
            references: fixture.references(),
        )
        await model.refresh()
        model.skipCurrent()
        let previous = try #require(model.state.progress)
        if failRefresh {
            try await fixture.store.perform {
                _ = try await fixture.store.rotateDataGeneration(
                    reason: .accountReset,
                    changedBy: RecordingReviewTestSupport.first,
                    at: RecordingReviewTestSupport.date(2000),
                )
            }
            await model.refresh()
        }
        let cancelled = Task { await model.reviewRemaining() }
        cancelled.cancel()
        await cancelled.value
        #expect(model.state.progress?.skipped == previous.skipped)
        #expect(model.state.progress?.remaining == previous.remaining)
        if failRefresh {
            guard case let .failed(error, _) = model.state else {
                Issue.record("A cancelled retry must not erase the failed reassessment")
                return
            }
            #expect(error as? RecordingReviewQueue.ValidationError == .dataGenerationChanged)
        } else {
            guard case .pending = model.state else {
                Issue.record("A cancelled retry must leave skipped work pending")
                return
            }
        }
    }

    @Test func reviewRemainingCannotReviveWorkAfterScopeRetirement() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try await RecordingReviewFlowModel(
            services: fixture.services,
            references: fixture.references(),
        )
        await model.refresh()
        model.skipCurrent()
        await fixture.services.retireCompatibilityScope()
        await model.reviewRemaining()
        guard case .failed(_, previous: nil) = model.state else {
            Issue.record("Retired access must clear the retained queue presentation")
            return
        }
        #expect(!model.queue.references.isEmpty)
    }

    @Test func skippingKeepsTheOriginalWorkPendingUntilSuccessfulReassessment() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let references = try await fixture.references()
        let model = try RecordingReviewFlowModel(services: fixture.services, references: references)
        await model.refresh()
        let item = try #require(model.state.progress?.current)
        model.skipCurrent()
        #expect(model.state.progress?.current == nil)
        #expect(model.state.progress?.remaining.count == 1)
        #expect(model.queue.references == Set(references))
        await model.reviewRemaining()
        #expect(model.state.progress?.current?.periods == item.periods)
        let choice = RecordingChoiceModel(services: fixture.services, periods: item.periods)
        await choice.review(.init(
            scope: .periods(item.periods),
            action: .select(RecordingReviewTestSupport.first),
        ))
        await choice.apply()
        #expect(choice.didApply)
        await model.refresh()
        guard case .resolved = model.state else {
            Issue.record("Successful complete reassessment must find no remaining work")
            return
        }
    }

    @Test func unrelatedNewWorkDoesNotExtendTheOriginalQueue() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let references = try await fixture.references()
        let model = try RecordingReviewFlowModel(services: fixture.services, references: references)
        await model.refresh()
        let original = model.queue.originalPeriods
        let item = try #require(model.state.progress?.current)
        let newer = try [20000.0, 20600, 21200].flatMap { seconds in
            try [RecordingReviewTestSupport.first, RecordingReviewTestSupport.second].map {
                try RecordingReviewTestSupport.sample(deviceID: $0, seconds: seconds)
            }
        }
        try await fixture.add(newer)
        await model.refresh()
        #expect(model.queue.originalPeriods == original)
        #expect(model.state.progress?.remaining.count == 1)
        #expect(model.state.progress?.current?.periods == item.periods)
        let current = try await fixture.services.resolution.historicalScan(
            driftThresholdMeters: 1000,
            force: true,
        )
        #expect(current.recording.issues.count == 2)
    }

    @Test(arguments: [false, true])
    func interruptedRefreshNeverReportsResolution(revoke: Bool) async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try await RecordingReviewFlowModel(
            services: fixture.services,
            references: fixture.references(),
        )
        await model.refresh()
        let previous = try #require(model.state.progress?.remaining)
        let hold = ResolutionScanSuspension()
        await fixture.services.resolution
            .setBeforeRecordingReviewPublicationForTesting { await hold.suspendFirst() }
        let pending = Task { await model.refresh() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        if revoke { await fixture.services.retireCompatibilityScope() } else { pending.cancel() }
        hold.resume()
        await pending.value
        if revoke {
            guard case .failed(_, previous: nil) = model.state else {
                Issue.record("Revoked access must clear prior admitted work")
                return
            }
        } else {
            guard case .pending = model.state else {
                Issue.record("Cancellation must retain pending work")
                return
            }
            #expect(model.state.progress?.remaining == previous)
        }
        #expect(model.queue.references.isEmpty == false)
    }

    @Test func deactivationRejectsACompletedOldQueueRefresh() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try await RecordingReviewFlowModel(
            services: fixture.services,
            references: fixture.references(),
        )
        let hold = ResolutionScanSuspension()
        await fixture.services.resolution
            .setBeforeRecordingReviewPublicationForTesting { await hold.suspendFirst() }
        let pending = Task { await model.refresh() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        model.deactivate()
        hold.resume()
        await pending.value
        guard case .idle = model.state else {
            Issue.record("A closed flow must not publish its late refresh")
            return
        }
    }

    @Test func generationChangeIsAFailureWithPendingWorkNotResolution() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try await RecordingReviewFlowModel(
            services: fixture.services,
            references: fixture.references(),
        )
        await model.refresh()
        let previous = try #require(model.state.progress?.remaining)
        try await fixture.store.perform {
            _ = try await fixture.store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: RecordingReviewTestSupport.first,
                at: RecordingReviewTestSupport.date(2000),
            )
        }
        await model.refresh()
        guard case let .failed(error, pending) = model.state else {
            Issue.record("A new generation cannot complete old queued work")
            return
        }
        #expect(error as? RecordingReviewQueue.ValidationError == .dataGenerationChanged)
        #expect(pending?.remaining == previous)
    }
}
