import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingPlaceInspectionTests {
    @Test func ongoingReviewDetectsFutureDefinitionsAndRetainsTheExactPreviewOnRetry() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let original = try RecordingControlsTestSupport.place(1, end: nil)
        try await RecordingChoiceTestSupport.append(.place(original), store: store)
        let edit = try RecordingControlEdit.place(
            placeID: original.placeID,
            validity: [.init(
                start: RecordingAssessmentTestSupport
                    .time(20),
                end: nil,
            )],
            action: .remove,
        )
        let proposal = try await coordinator.review(edit)
        let preview = try coordinator.inspectPlace(proposal)
        #expect(preview.changes.count == 1)
        #expect(preview.changes[0].period.end == nil)
        #expect(preview.changes[0].after == .absent)
        #expect(proposal.evidence.query.periods.isEmpty)
        let future = try RecordingControlsTestSupport.place(
            2,
            start: 1e8,
            end: nil,
            action: .set(
                kind: .regularHome,
                coordinate: .init(
                    latitude: 40,
                    longitude: -74,
                ),
            ),
            predecessors: [original.id],
        )
        try await RecordingChoiceTestSupport.append(.place(future), store: store)
        #expect(try coordinator.inspectPlace(proposal) == preview)
        guard case let .stale(refreshed) = try await coordinator.apply(proposal)
        else { Issue.record("A future definition changed the ongoing scope"); return }
        let updated = try coordinator.inspectPlace(refreshed)
        #expect(updated.changes.count == 2)
        #expect(updated.changes.last?.period.end == nil)
        #expect(updated.changes.last?.before == .place(
            kind: .regularHome,
            coordinate: .init(
                latitude: 40,
                longitude: -74,
            ),
        ))
        #expect(try await coordinator.apply(refreshed) == .applied)
        #expect(try await coordinator.apply(refreshed) == .applied)
        let saved = try await coordinator.placeHistory()
        #expect(saved.entries[0].decisions.count == 3)
        #expect(saved.entries[0].segments.last?.period.end == nil)
        #expect(saved.entries[0].segments.last?.resolution == .absent)
        #expect(saved.entries[0].segments.first?.period.end == RecordingAssessmentTestSupport
            .time(20))
    }

    @Test func unrelatedObservationsAndPlacesDoNotChangeADefinitionOnlyPreview() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let proposal = try await coordinator.review(.place(
            placeID: RecordingControlsTestSupport.placeID,
            validity: [.init(start: RecordingAssessmentTestSupport.time(0), end: nil)],
            action: .set(kind: .regularHome, coordinate: .init(latitude: 37, longitude: -122)),
        ))
        let other = try RecordingControlsTestSupport.place(
            2,
            end: nil,
            placeID: .init(rawValue: RecordingControlsTestSupport
                .otherDevice.rawValue),
        )
        try await RecordingChoiceTestSupport.append(.place(other), store: store)
        let sample = try RecordingChoiceTestSupport.sample(seconds: 40)
        try await store.perform { try await store.add(sample: sample) }
        #expect(try await coordinator.apply(proposal) == .applied)
        #expect(try await store.allSamples() == [sample])
        #expect(try await coordinator.placeHistory().entries.count == 2)
    }

    @Test func inspectionKeepsReviewedEvidenceUntilStaleApplyReturnsAnotherProposal() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let proposal = try await coordinator.review(RecordingControlEditTestSupport.edit(
            .place,
            removes: false,
        ))
        let preview = try coordinator.inspectPlace(proposal)
        #expect(preview.placeID == RecordingControlsTestSupport.placeID)
        #expect(preview.changes.count == 1)
        #expect(preview.changes[0].before == .absent)
        #expect(preview.changes[0].after == .place(
            kind: .regularHome,
            coordinate: .init(latitude: 37, longitude: -122),
        ))
        #expect(try await coordinator.placeHistory().entries.isEmpty)

        let late = try RecordingControlsTestSupport.place(
            10,
            start: 100,
            end: 200,
            action: .set(kind: .temporaryBase, coordinate: .init(latitude: 40, longitude: -73)),
        )
        try await RecordingChoiceTestSupport.append(.place(late), store: store)
        #expect(try coordinator.inspectPlace(proposal) == preview)
        guard case let .stale(refreshed) = try await coordinator.apply(proposal)
        else { Issue.record("An unreviewed place must refresh the proposal before saving"); return }
        let updated = try coordinator.inspectPlace(refreshed)
        #expect(updated.changes.count == 3)
        #expect(updated.changes[1].before == .place(
            kind: .temporaryBase,
            coordinate: .init(latitude: 40, longitude: -73),
        ))
        #expect(updated.changes.allSatisfy { $0.after == preview.changes[0].after })
        #expect(try await coordinator.placeHistory().entries[0].decisions == [late])
        #expect(try await coordinator.apply(refreshed) == .applied)
        let saved = try await coordinator.placeHistory()
        #expect(saved.entries[0].decisions.count == 2)
        #expect(saved.entries[0].segments.allSatisfy {
            RecordingPlaceInspection.Definition($0.resolution) == preview.changes[0].after
        })
    }

    @Test func removalPreservesUnreviewedGapsAndOtherPlaceIdentities() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let original = try RecordingControlsTestSupport.place(1, end: 1000)
        let other = try RecordingControlsTestSupport.place(
            2,
            end: 1000,
            placeID: .init(rawValue: RecordingControlsTestSupport.otherDevice.rawValue),
        )
        try await RecordingChoiceTestSupport.append(.place(original), store: store)
        try await RecordingChoiceTestSupport.append(.place(other), store: store)
        let periods = try [
            RecordingAssessmentTestSupport.period(100, 200),
            RecordingAssessmentTestSupport.period(400, 500),
        ]
        let proposal = try await coordinator.review(.place(
            placeID: original.placeID,
            periods: periods,
            action: .remove,
        ))
        let preview = try coordinator.inspectPlace(proposal)
        #expect(try preview.changes.map(\.period) == periods.map(RecordingInterval.init))
        #expect(preview.changes.allSatisfy {
            $0.before == .place(
                kind: .regularHome,
                coordinate: .init(latitude: 37, longitude: -122),
            ) && $0.after == .absent
        })
        #expect(try await coordinator.apply(proposal) == .applied)
        let history = try await coordinator.placeHistory()
        let entry = try #require(history.entries.first { $0.placeID == original.placeID })
        #expect(entry.segments.map { RecordingPlaceInspection.Definition($0.resolution) } == [
            preview.changes[0].before,
            .absent,
            preview.changes[0].before,
            .absent,
            preview.changes[0].before,
        ])
        #expect(history.entries.first { $0.placeID == other.placeID }?.decisions == [other])
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func reviewedResolutionKeepsUnknownScopesAndMissingPredecessorUncertainty() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let original = try RecordingControlsTestSupport.place(1)
        let rival = try RecordingControlsTestSupport.place(2, start: 20, end: 40, action: .remove)
        let missing = try RecordingControlsTestSupport.place(3)
        let incomplete = try RecordingControlsTestSupport.place(
            4,
            start: 60,
            end: 80,
            predecessors: [missing.id],
        )
        for place in [original, rival, incomplete] {
            try await RecordingChoiceTestSupport.append(.place(place), store: store)
        }
        let opaque = try VersionedHistoryRecord(
            id: .init(rawValue: UUID()),
            dataGenerationID: .initial,
            semantics: .init(major: 1, minor: 1, patch: 0),
            scope: .periods([RecordingAssessmentTestSupport.period(25, 30)]),
            kind: "recording.future-control",
            payload: Data([1]),
        )
        try await store.perform { try await store.addVersionedHistoryRecord(opaque) }
        let proposal = try await coordinator.review(.place(
            placeID: original.placeID,
            periods: [RecordingAssessmentTestSupport.period(0, 100)],
            action: .remove,
        ))
        let preview = try coordinator.inspectPlace(proposal)
        #expect(preview.changes[1].before == .conflict([original.id, rival.id]))
        // The replacement names the incomplete operation as a predecessor. Its missing
        // dependency remains unresolved throughout the replacement's complete scope.
        #expect(preview.changes.allSatisfy { $0.after == .incomplete([missing.id]) })
        #expect(preview.changes[3].before == .incomplete([missing.id]))
        #expect(preview.changes[3].after == .incomplete([missing.id]))
        #expect(preview.unknownControls == [opaque])
        #expect(try await coordinator.apply(proposal) == .applied)
        let saved = try await coordinator.placeHistory()
        #expect(saved.unknownControls == [opaque])
        #expect(saved.entries[0].segments.contains { $0.resolution == .incomplete([missing.id]) })
    }

    @Test func inspectionRejectsMixedFamiliesAndSeveralPlaceIdentities() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let place = try RecordingControlEditTestSupport.edit(.place, removes: false)
        let calendar = try RecordingControlEditTestSupport.edit(.calendar, removes: false)
        let mixed = try await coordinator.review([place, calendar])
        #expect(throws: RecordingPlaceInspection.ValidationError.notAPlace) {
            try coordinator.inspectPlace(mixed)
        }
        let other = try RecordingControlEdit.place(
            placeID: .init(rawValue: RecordingControlsTestSupport.otherDevice.rawValue),
            periods: [RecordingAssessmentTestSupport.period(0, 100)],
            action: .remove,
        )
        let multiple = try await coordinator.review([place, other])
        #expect(throws: RecordingPlaceInspection.ValidationError.multiplePlaces) {
            try coordinator.inspectPlace(multiple)
        }
    }
}
