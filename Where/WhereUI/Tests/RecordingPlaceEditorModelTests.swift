import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct RecordingPlaceEditorModelTests {
    @Test func creatingAHomeRequiresExplicitCoordinatesAndKeepsOneIdentity() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = RecordingPlaceEditorModel(
            services: fixture.services,
            intent: .new(at: RecordingReviewTestSupport.date(0)),
        )
        #expect(throws: RecordingPlaceEditorModel.DraftError.coordinateRequired) {
            try model.edits.get()
        }
        await model.review()
        #expect(model.controls.state.review == nil)
        guard case let .definition(definition) = model.draft else {
            Issue.record("Expected definition draft"); return
        }
        definition.coordinate = RecordingPlaceTestSupport.coordinate
        await model.review()
        let first = try #require(model.controls.state.review?.proposal)
        await model.review()
        #expect(model.controls.state.review?.proposal.evidence.query == first.evidence.query)
        #expect(try await fixture.controls().places.isEmpty)
        await model.apply()
        let saved = try #require(await fixture.controls().places.first)
        #expect(saved.placeID == model.placeID)
        #expect(saved.periods.first?.start == RecordingReviewTestSupport.date(0))
        #expect(saved.periods.first?.end == nil)
    }

    @Test func temporaryBasesRequireAnEndAndInvalidCoordinatesNeverReachReview() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try RecordingPlaceTestSupport.editor(fixture)
        guard case let .definition(definition) = model.draft else {
            Issue.record("Expected definition draft"); return
        }
        definition.kind = .temporaryBase
        #expect(throws: RecordingPlaceEditorModel.DraftError.endRequired) { try model.edits.get() }
        await model.review()
        #expect(!model.canApply)
        model.bounds.end = RecordingReviewTestSupport.date(1200)
        definition.coordinate = .init(latitude: .nan, longitude: 0)
        #expect(throws: RecordingPlace.ValidationError.invalidCoordinate) { try model.edits.get() }
        definition.coordinate = RecordingPlaceTestSupport.coordinate
        await model.review()
        #expect(model.canApply)
        await model.apply()
        let saved = try #require(await fixture.controls().places.first)
        #expect(saved.periods.first?.end == RecordingReviewTestSupport.date(1200))
        #expect(saved.action == .set(
            kind: .temporaryBase,
            coordinate: RecordingPlaceTestSupport.coordinate,
        ))
    }

    @Test func changingADraftInvalidatesApplyAndLostReceiptRetryKeepsTheOperation() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try RecordingPlaceTestSupport.editor(fixture)
        await model.review()
        let original = try #require(model.controls.state.review?.proposal)
        model.bounds.start = RecordingReviewTestSupport.date(600)
        #expect(!model.canApply)
        #expect(model.inspection == nil)
        await model.apply()
        #expect(try await fixture.controls().places.isEmpty)
        model.bounds.start = RecordingReviewTestSupport.date(0)
        model.controls.setBeforePublicationForTesting {
            throw RecordingReviewTestSupport.TestFailure.interruptedSaveReceipt
        }
        await model.apply()
        #expect(model.canRetry)
        model.bounds.end = RecordingReviewTestSupport.date(1200)
        #expect(!model.canRetry)
        await model.retry()
        #expect(model.controls.state.review?.proposal == original)
        model.bounds.end = nil
        model.controls.setBeforePublicationForTesting {}
        await model.retry()
        #expect(model.controls.didApply)
        #expect(try await fixture.controls().places.count == 1)
    }

    @Test func aLaterDefinitionRequiresAnotherExplicitApplyOfTheRefreshedPreview() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try RecordingPlaceTestSupport.editor(fixture)
        await model.review()
        let coordinator = fixture.services.recordingControlEdits
        let later = try await coordinator.review(.place(
            placeID: model.placeID,
            validity: [.init(start: RecordingReviewTestSupport.date(86400), end: nil)],
            action: .set(kind: .regularHome, coordinate: .init(latitude: 51.5, longitude: 0)),
        ))
        #expect(try await coordinator.apply(later) == .applied)
        await model.apply()
        #expect(model.controls.state.review?.refreshed == true)
        let preview = try #require(model.inspection).get()
        #expect(preview.changes.count == 2)
        #expect(preview.changes.last?.before == .place(
            kind: .regularHome,
            coordinate: .init(latitude: 51.5, longitude: 0),
        ))
        #expect(try await fixture.controls().places.count == 1)
        #expect(model.canApply)
        await model.apply()
        #expect(model.controls.didApply)
        #expect(try await fixture.controls().places.count == 2)
    }

    @Test func endingAHomePreservesItsEarlierDefinition() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let saved = try await RecordingPlaceTestSupport.save(fixture)
        let cutoff = RecordingReviewTestSupport.date(600)
        let model = try RecordingPlaceEditorModel(
            services: fixture.services,
            intent: .remove(placeID: saved.placeID, validity: .init(start: cutoff, end: nil)),
        )
        await model.review()
        let preview = try #require(model.inspection).get()
        #expect(preview.changes.first?.period.start == cutoff)
        #expect(preview.changes.first?.after == .absent)
        await model.apply()
        let history = try await fixture.services.recordingControlEdits.placeHistory()
        let segments = try #require(history.entries.first).segments
        #expect(segments.count == 2)
        guard case .place = segments[0].resolution else {
            Issue.record("Earlier home must remain valid"); return
        }
        #expect(segments[0].period.end == cutoff)
        #expect(segments[1].resolution == .absent)
        #expect(segments[1].period.end == nil)
    }

    @Test func shorteningAnOngoingHomeDoesNotResurrectItsOldTail() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let saved = try await RecordingPlaceTestSupport.save(fixture)
        let model = try RecordingPlaceEditorModel(
            services: fixture.services,
            intent: .definition(
                placeID: saved.placeID,
                kind: .regularHome,
                coordinate: RecordingPlaceTestSupport.coordinate,
                validity: #require(saved.periods.first),
            ),
        )
        model.bounds.end = RecordingReviewTestSupport.date(600)
        await model.review()
        let preview = try #require(model.inspection).get()
        #expect(preview.changes.count == 2)
        #expect(preview.changes.last?.after == .absent)
        #expect(preview.changes.last?.period.end == nil)
        await model.apply()
        let history = try await fixture.services.recordingControlEdits.placeHistory()
        let entry = try #require(history.entries.first)
        #expect(entry.segments.count == 2)
        #expect(entry.segments.last?.resolution == .absent)
        #expect(entry.segments.last?.period.start == RecordingReviewTestSupport.date(600))
        #expect(entry.decisions.allSatisfy { $0.placeID == saved.placeID })
    }

    @Test func draftChangeAndRetirementRejectLateReviewPublication() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let model = try RecordingPlaceTestSupport.editor(fixture)
        let hold = ResolutionScanSuspension()
        model.controls.setBeforePublicationForTesting { await hold.suspendFirst() }
        let read = Task { await model.review() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        guard case let .definition(definition) = model.draft else {
            hold.resume(); await read.value
            Issue.record("Expected definition draft"); return
        }
        definition.coordinate = .init(latitude: 51.5, longitude: 0)
        hold.resume()
        await read.value
        #expect(!model.canApply)
        #expect(model.inspection == nil)
        model.deactivate()
        await model.review()
        await model.apply()
        #expect(model.controls.state.review == nil)
        #expect(try await fixture.controls().places.isEmpty)
    }
}
