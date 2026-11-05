import Foundation
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct RecordingIgnoreModelTests {
    @Test func foregroundReentryRefreshesHistoryWithoutRetiringAnOpenEditor() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingIgnoreTestSupport.model(fixture)
        let firstObservation = Task { await model.run() }
        try await CompatibilityLaunchFixture.waitUntil { model.state.history != nil }
        model.start(timeZone: .gmt)
        let editor = try #require(model.editor)
        await editor.review()
        model.pause()
        firstObservation.cancel()
        await firstObservation.value
        #expect(model.editor === editor)
        #expect(editor.canApply)
        _ = try await RecordingIgnoreTestSupport.ignore(
            fixture: fixture,
            deviceID: RecordingReviewTestSupport.first,
            day: RecordingReviewTestSupport.day,
        )
        let nextObservation = Task { await model.run() }
        try await CompatibilityLaunchFixture.waitUntil { model.state.history?.decisions.count == 1 }
        #expect(model.editor === editor)
        model.deactivate()
        nextObservation.cancel()
        await nextObservation.value
        #expect(!editor.canApply)
        #expect(model.state.history == nil)
    }

    @Test func releasingTheOwnerPermanentlyRetiresItsEditor() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        var model: RecordingIgnoreModel? = RecordingIgnoreTestSupport.model(fixture)
        await model?.refresh()
        model?.start(timeZone: .gmt)
        let editor = try #require(model?.editor)
        await editor.review()
        #expect(editor.canApply)
        weak var owner = model
        model = nil
        try await CompatibilityLaunchFixture.waitUntil { owner == nil && !editor.canApply }
        await editor.review()
        #expect(editor.controls.state.review == nil)
    }

    @Test func anIntentDetectingRevokedAccessRetiresRetainedHistoryAndEditor() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingIgnoreTestSupport.model(fixture)
        await model.refresh()
        model.start(timeZone: .gmt)
        let editor = try #require(model.editor)
        await editor.review()
        #expect(editor.canApply)
        await fixture.services.retireCompatibilityScope()
        model.start(timeZone: .gmt)
        #expect(model.state.history == nil)
        #expect(model.editor == nil)
        #expect(!editor.canApply)
        #expect(model.actionError != nil)
        guard case let .failed(error, previous) = model.state
        else { Issue.record("Revoked access must remain visible"); return }
        #expect(previous == nil)
        #expect(error as? DataCompatibilityAccess.AccessError == .revoked)
        #expect(model.actionError as? DataCompatibilityAccess.AccessError == .revoked)
    }

    @Test func committedRefreshKeepsTheEditorAndItsFailedSaveIdentity() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingIgnoreTestSupport.model(fixture)
        let observation = Task { await model.run() }
        defer { observation.cancel() }
        try await CompatibilityLaunchFixture.waitUntil { model.state.history != nil }
        model.start(timeZone: .gmt)
        let editor = try #require(model.editor)
        await editor.review()
        let proposal = try #require(editor.controls.state.review?.proposal)
        editor.controls.setBeforePublicationForTesting {
            throw RecordingReviewTestSupport.TestFailure.interruptedSaveReceipt
        }
        await editor.apply()
        try await CompatibilityLaunchFixture.waitUntil { model.state.history?.decisions.count == 1 }
        #expect(model.editor === editor)
        #expect(editor.controls.state.review?.proposal == proposal)
        #expect(editor.canRetry)
        model.editor = nil
        await editor.review()
        #expect(editor.controls.state.review == nil)
        model.deactivate()
        observation.cancel()
        await observation.value
        #expect(model.state.history == nil)
    }

    @Test func refreshFailureKeepsHistoryAndTheOriginalError() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingIgnoreTestSupport.model(fixture)
        await model.refresh()
        let history = try #require(model.state.history)
        model.setBeforePublicationForTesting {
            throw RecordingReviewTestSupport.TestFailure.expectedPreview
        }
        await model.refresh()
        guard case let .failed(error, previous) = model.state
        else { Issue.record("Expected a visible read failure"); return }
        #expect(error as? RecordingReviewTestSupport.TestFailure == .expectedPreview)
        #expect(previous == history)
        model.setBeforePublicationForTesting {}
        await model.refresh()
        guard case .loaded = model.state
        else { Issue.record("Retry should restore the read state"); return }
    }

    enum Interruption: CaseIterable { case cancellation, disappearance, deactivation, revocation }

    @Test(arguments: Interruption.allCases)
    func lateHistoryCannotSurviveCancellationRetirementOrRevocation(
        interruption: Interruption,
    ) async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingIgnoreTestSupport.model(fixture)
        let hold = ResolutionScanSuspension()
        model.setBeforePublicationForTesting { await hold.suspendFirst() }
        let read = Task { await model.refresh() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        switch interruption {
            case .cancellation: read.cancel()
            case .disappearance: model.pause()
            case .deactivation: model.deactivate()
            case .revocation: await fixture.services.retireCompatibilityScope()
        }
        hold.resume()
        await read.value
        #expect(model.state.history == nil)
        model.start(timeZone: .gmt)
        #expect(model.editor == nil)
    }

    @Test func aSupersededReadCannotReplaceNewerHistory() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingIgnoreTestSupport.model(fixture)
        let hold = ResolutionScanSuspension()
        model.setBeforePublicationForTesting { await hold.suspendFirst() }
        let read = Task { await model.refresh() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        let decision = try await RecordingIgnoreTestSupport.ignore(
            fixture: fixture,
            deviceID: RecordingReviewTestSupport.first,
            day: RecordingReviewTestSupport.day,
        )
        await model.refresh()
        hold.resume()
        await read.value
        #expect(model.state.history?.decisions == [decision])
        model.resume(decision)
        let editor = try #require(model.editor)
        await editor.review()
        #expect(editor.canApply)
        #expect(editor.controls.state.review?.proposal.evidence.query.periods.first?
            .start == RecordingReviewTestSupport.date(600))
    }
}
