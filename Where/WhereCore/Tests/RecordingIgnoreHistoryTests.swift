import Foundation
import Testing
@testable import WhereCore

struct RecordingIgnoreHistoryTests {
    @Test func resumedAndUndonePeriodsRemainDurableWithoutJoiningGaps() throws {
        let original = try RecordingControlsTestSupport.ignore(1)
        let resume = try RecordingControlsTestSupport.ignore(
            2,
            start: 400,
            change: .restoreEligibility,
            predecessors: [original.id],
        )
        let undo = try RecordingControlsTestSupport.ignore(
            3,
            start: 0,
            end: 200,
            change: .restoreEligibility,
            predecessors: [original.id],
        )
        let later = try RecordingControlsTestSupport.ignore(
            4,
            start: 172_800,
            end: 259_200,
            change: .ignore(.init(day: .init(year: 2001, month: 1, day: 3), timeZone: .gmt)),
        )
        let other = try RecordingControlsTestSupport.ignore(
            5,
            deviceID: RecordingControlsTestSupport.otherDevice,
        )
        let source = try RecordingAssessmentTestSupport.decision(6, end: 86400)
        let controls: [RecordingControl] = [
            .ignore(original),
            .ignore(resume),
            .ignore(undo),
            .ignore(later),
            .ignore(other),
            .source(source),
        ]
        let history = try RecordingIgnoreHistory(
            controls: RecordingControlSelectionTestSupport.snapshot(controls),
            deviceID: original.deviceID,
            version: original.version,
        )
        #expect(Set(history.decisions.map(\.id)) == [original.id, resume.id, undo.id, later.id])
        #expect(history.decisions.first == later)
        #expect(history.segments.map(\.resolution) == [.eligible, .ignored, .eligible, .ignored])
        #expect(try history.segments.map(\.period) == [
            RecordingAssessmentTestSupport.period(0, 200),
            RecordingAssessmentTestSupport.period(200, 400),
            RecordingAssessmentTestSupport.period(400, 86400),
            RecordingAssessmentTestSupport.period(172_800, 259_200),
        ])
        #expect(try history == RecordingIgnoreHistory(
            controls: RecordingControlSelectionTestSupport.snapshot(controls.reversed()),
            deviceID: original.deviceID,
            version: original.version,
        ))
        #expect(history.generationID == .initial)
        #expect(history.policyVersion == original.version)
    }

    @Test func conflictsMissingParentsAndUnknownControlsRemainVisible() throws {
        let original = try RecordingControlsTestSupport.ignore(1)
        let restore = try RecordingControlsTestSupport.ignore(
            2,
            start: 100,
            end: 200,
            change: .restoreEligibility,
        )
        let missing = try RecordingControlsTestSupport.ignore(3)
        let incomplete = try RecordingControlsTestSupport.ignore(
            4,
            start: 300,
            end: 400,
            change: .restoreEligibility,
            predecessors: [missing.id],
        )
        let values: [RecordingControl] = [.ignore(original), .ignore(restore), .ignore(incomplete)]
        let opaque = try VersionedHistoryRecord(
            id: .init(rawValue: UUID()),
            dataGenerationID: .initial,
            semantics: .init(major: 1, minor: 1, patch: 0),
            scope: .entireHistory,
            kind: "recording.future-control",
            payload: Data([1]),
        )
        let snapshot = try RecordingControlSnapshot(
            records: values.map { try RecordingControlCodec.encode($0, generationID: .initial) }
                + [opaque],
            generationID: .initial,
            policy: RecordingChoiceTestSupport.policy,
        )
        let history = try RecordingIgnoreHistory(
            controls: snapshot,
            deviceID: original.deviceID,
            version: original.version,
        )
        #expect(history.segments.map(\.resolution) == [
            .ignored,
            .conflict([original.id, restore.id]),
            .ignored,
            .incomplete([missing.id]),
            .ignored,
        ])
        #expect(history.unknownControls == [opaque])
        #expect(history.segments[1].effectiveDecisions == [original.id, restore.id])
    }

    @Test func noIgnoreHistoryDoesNotEraseUnknownSharedControls() throws {
        let opaque = try VersionedHistoryRecord(
            id: .init(rawValue: UUID()),
            dataGenerationID: .initial,
            semantics: .init(major: 1, minor: 1, patch: 0),
            scope: .periods([RecordingAssessmentTestSupport.period(100, 200)]),
            kind: "recording.future-control",
            payload: Data([1]),
        )
        let snapshot = try RecordingControlSnapshot(
            records: [opaque],
            generationID: .initial,
            policy: RecordingChoiceTestSupport.policy,
        )
        let history = try RecordingIgnoreHistory(
            controls: snapshot,
            deviceID: RecordingControlsTestSupport.device,
            version: RecordingEvidencePolicy.version,
        )
        #expect(history.decisions.isEmpty)
        #expect(history.segments.isEmpty)
        #expect(history.unknownControls == [opaque])
    }
}
