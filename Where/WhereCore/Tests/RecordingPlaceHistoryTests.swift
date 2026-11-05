import Foundation
import Testing
@testable import WhereCore

struct RecordingPlaceHistoryTests {
    @Test func historicalDefinitionsAndRemovalsRetainValidityGapsAndIdentities() throws {
        let first = try RecordingControlsTestSupport.place(1)
        let removed = try RecordingControlsTestSupport.place(
            2,
            start: 40,
            end: 60,
            action: .remove,
            predecessors: [first.id],
        )
        let later = try RecordingControlsTestSupport.place(
            3,
            start: 200,
            end: 300,
            action: .set(kind: .temporaryBase, coordinate: .init(latitude: 40, longitude: -73)),
        )
        let other = try RecordingControlsTestSupport.place(
            4,
            placeID: .init(rawValue: RecordingControlsTestSupport.otherDevice.rawValue),
        )
        let controls: [RecordingControl] = [
            .place(first),
            .place(removed),
            .place(later),
            .place(other),
        ]
        let history = try RecordingPlaceHistory(
            controls: RecordingControlSelectionTestSupport.snapshot(controls),
            version: RecordingEvidencePolicy.version,
        )
        #expect(history.entries.count == 2)
        let entry = try #require(history.entries.first { $0.placeID == first.placeID })
        #expect(entry.decisions == [later, removed, first])
        #expect(try entry.segments.map(\.period) == [
            RecordingAssessmentTestSupport.period(0, 40),
            RecordingAssessmentTestSupport.period(40, 60),
            RecordingAssessmentTestSupport.period(60, 100),
            RecordingAssessmentTestSupport.period(200, 300),
        ])
        #expect(entry.segments[1].resolution == .absent)
        guard case let .place(old) = entry.segments[0].resolution,
              case let .place(new) = entry.segments[3].resolution
        else { Issue.record("Both historical definitions must remain visible"); return }
        #expect(old.kind == .regularHome)
        #expect(new.kind == .temporaryBase)
        #expect(old.coordinate != new.coordinate)
        #expect(old.id == new.id)
        #expect(try history == RecordingPlaceHistory(
            controls: RecordingControlSelectionTestSupport.snapshot(controls.reversed()),
            version: RecordingEvidencePolicy.version,
        ))
        #expect(history.generationID == .initial)
        #expect(history.policyVersion == RecordingEvidencePolicy.version)
    }

    @Test func conflictingAndIncompleteDefinitionsRemainUnresolved() throws {
        let original = try RecordingControlsTestSupport.place(1)
        let conflicting = try RecordingControlsTestSupport.place(
            2,
            start: 20,
            end: 40,
            action: .remove,
        )
        let missing = try RecordingControlsTestSupport.place(3)
        let incomplete = try RecordingControlsTestSupport.place(
            4,
            start: 60,
            end: 80,
            action: .remove,
            predecessors: [missing.id],
        )
        let history = try RecordingPlaceHistory(
            controls: RecordingControlSelectionTestSupport.snapshot([
                .place(original),
                .place(conflicting),
                .place(incomplete),
            ]),
            version: RecordingEvidencePolicy.version,
        )
        let entry = try #require(history.entries.first)
        #expect(entry.decisions.count == 3)
        #expect(entry.segments[1].resolution == .conflict([original.id, conflicting.id]))
        #expect(entry.segments[3].resolution == .incomplete([missing.id]))
        #expect(entry.segments[1].effectiveDecisions == [original.id, conflicting.id])
    }

    @Test func emptyDefinitionsDoNotDiscardUnknownSharedControls() throws {
        let opaque = VersionedHistoryRecord(
            id: .init(rawValue: UUID()),
            dataGenerationID: .initial,
            semantics: .init(major: 1, minor: 1, patch: 0),
            scope: .entireHistory,
            kind: "recording.future-control",
            payload: Data([1]),
        )
        let snapshot = try RecordingControlSnapshot(
            records: [opaque],
            generationID: .initial,
            policy: RecordingChoiceTestSupport.policy,
        )
        let history = try RecordingPlaceHistory(
            controls: snapshot,
            version: RecordingEvidencePolicy.version,
        )
        #expect(history.entries.isEmpty)
        #expect(history.unknownControls == [opaque])
    }
}
