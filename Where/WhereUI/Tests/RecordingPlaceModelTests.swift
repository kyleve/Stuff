import Foundation
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct RecordingPlaceModelTests {
    @Test func foregroundReentryRefreshesHistoryWithoutRetiringAnOpenEditor() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingPlaceTestSupport.model(fixture)
        let firstObservation = Task { await model.run() }
        try await CompatibilityLaunchFixture.waitUntil { model.state.history != nil }
        model.start()
        let editor = try #require(model.editor)
        if case let .definition(definition) = editor.draft {
            definition.coordinate = RecordingPlaceTestSupport.coordinate
        }
        await editor.review()
        model.pause()
        firstObservation.cancel()
        await firstObservation.value
        #expect(model.editor === editor)
        #expect(editor.canApply)
        _ = try await RecordingPlaceTestSupport.save(fixture)
        let nextObservation = Task { await model.run() }
        try await CompatibilityLaunchFixture.waitUntil { model.state.history?.entries.count == 1 }
        #expect(model.editor === editor)
        model.deactivate()
        nextObservation.cancel()
        await nextObservation.value
        #expect(!editor.canApply)
        #expect(model.state.history == nil)
    }

    @Test func releasingTheOwnerPermanentlyRetiresItsEditor() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        var model: RecordingPlaceModel? = RecordingPlaceTestSupport.model(fixture)
        await model?.refresh()
        model?.start()
        let editor = try #require(model?.editor)
        if case let .definition(definition) = editor.draft {
            definition.coordinate = RecordingPlaceTestSupport.coordinate
        }
        await editor.review()
        #expect(editor.canApply)
        weak var owner = model
        model = nil
        try await CompatibilityLaunchFixture.waitUntil { owner == nil && !editor.canApply }
        if case let .definition(definition) = editor.draft {
            definition.coordinate = RecordingPlaceTestSupport.coordinate
        }
        await editor.review()
        #expect(editor.controls.state.review == nil)
    }

    @Test func anIntentDetectingRevokedAccessRetiresRetainedHistoryAndEditor() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingPlaceTestSupport.model(fixture)
        await model.refresh()
        model.start()
        let editor = try #require(model.editor)
        if case let .definition(definition) = editor.draft {
            definition.coordinate = RecordingPlaceTestSupport.coordinate
        }
        await editor.review()
        #expect(editor.canApply)
        await fixture.services.retireCompatibilityScope()
        model.start()
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
        let model = RecordingPlaceTestSupport.model(fixture)
        let observation = Task { await model.run() }
        defer { observation.cancel() }
        try await CompatibilityLaunchFixture.waitUntil { model.state.history != nil }
        model.start()
        let editor = try #require(model.editor)
        if case let .definition(definition) = editor.draft {
            definition.coordinate = RecordingPlaceTestSupport.coordinate
        }
        await editor.review()
        let proposal = try #require(editor.controls.state.review?.proposal)
        editor.controls.setBeforePublicationForTesting {
            throw RecordingReviewTestSupport.TestFailure.interruptedSaveReceipt
        }
        await editor.apply()
        try await CompatibilityLaunchFixture.waitUntil { model.state.history?.entries.count == 1 }
        #expect(model.editor === editor)
        #expect(editor.controls.state.review?.proposal == proposal)
        #expect(editor.canRetry)
        model.editor = nil
        if case let .definition(definition) = editor.draft {
            definition.coordinate = RecordingPlaceTestSupport.coordinate
        }
        await editor.review()
        #expect(editor.controls.state.review == nil)
        model.deactivate()
        observation.cancel()
        await observation.value
        #expect(model.state.history == nil)
    }

    @Test func refreshFailureKeepsHistoryAndTheOriginalError() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingPlaceTestSupport.model(fixture)
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
        let model = RecordingPlaceTestSupport.model(fixture)
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
        model.start()
        #expect(model.editor == nil)
    }

    @Test func aSupersededReadCannotReplaceNewerHistory() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingPlaceTestSupport.model(fixture)
        let hold = ResolutionScanSuspension()
        model.setBeforePublicationForTesting { await hold.suspendFirst() }
        let read = Task { await model.refresh() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        let decision = try await RecordingPlaceTestSupport.save(fixture)
        await model.refresh()
        hold.resume()
        await read.value
        let entry = try #require(model.state.history?.entries.first)
        #expect(entry.decisions == [decision])
        try model.edit(placeID: entry.placeID, segment: #require(entry.segments.first))
        let editor = try #require(model.editor)
        if case let .definition(definition) = editor.draft {
            definition.coordinate = RecordingPlaceTestSupport.coordinate
        }
        await editor.review()
        #expect(editor.canApply)
        #expect(editor.controls.state.review?.proposal.evidence.query.places.first?
            .placeID == decision.placeID)
    }

    @Test func conflictingHistoryNeverPrefillsAnArbitraryCoordinate() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let original = try await RecordingPlaceTestSupport.save(fixture)
        let conflict = try RecordingPlaceDecision(
            id: .init(rawValue: UUID()),
            author: RecordingReviewTestSupport.second,
            placeID: original.placeID,
            validity: original.periods,
            action: .set(kind: .regularHome, coordinate: .init(latitude: 51.5, longitude: 0)),
            predecessors: [],
            version: RecordingEvidencePolicy.version,
        )
        let record = try RecordingControlCodec.encode(.place(conflict), generationID: .initial)
        try await fixture.store
            .perform { try await fixture.store.addVersionedHistoryRecord(record) }
        let model = RecordingPlaceTestSupport.model(fixture)
        await model.refresh()
        let entry = try #require(model.state.history?.entries.first)
        let segment = try #require(entry.segments.first)
        #expect(segment.resolution == .conflict([original.id, conflict.id]))
        model.edit(placeID: entry.placeID, segment: segment)
        let editor = try #require(model.editor)
        guard case let .definition(definition) = editor.draft else {
            Issue.record("Expected definition draft"); return
        }
        #expect(definition.coordinate == nil)
        await editor.review()
        #expect(!editor.canApply)
        definition.coordinate = RecordingPlaceTestSupport.coordinate
        await editor.review()
        #expect(try editor.inspection?.get().changes.first?.before == .conflict([
            original.id,
            conflict.id,
        ]))
        await editor.apply()
        await model.refresh()
        guard case let .place(place) = model.state.history?.entries.first?.segments.first?
            .resolution
        else {
            Issue.record("Explicit definition must resolve complete conflict"); return
        }
        #expect(place.coordinate == RecordingPlaceTestSupport.coordinate)
    }
}
