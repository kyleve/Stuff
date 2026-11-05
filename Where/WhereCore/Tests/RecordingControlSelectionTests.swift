import Foundation
import Testing
@testable import WhereCore

struct RecordingControlSelectionTests {
    @Test func explicitSourcesBypassIgnoresRegardlessOfDeliveryOrderOrMissingIgnoreParents() throws {
        let source = try RecordingAssessmentTestSupport.decision(1, end: 86400)
        let ignore = try RecordingControlsTestSupport.ignore(10)
        let incompleteIgnore = try RecordingControlsTestSupport.ignore(
            11,
            predecessors: [.init(rawValue: RecordingAssessmentTestSupport.decisionID(12)
                    .rawValue)],
        )
        let variants: [[RecordingControl]] = [
            [.source(source), .ignore(ignore)],
            [.ignore(ignore), .source(source)],
            [.ignore(incompleteIgnore), .source(source)],
        ]
        for values in variants {
            let segments = try RecordingControlSelectionTestSupport.resolve(values)
            #expect(segments.allSatisfy { $0.resolution == .selected(source.author) })
        }
    }

    @Test func returningToAutomaticReappliesHistoricalIgnoreWithoutChangingOtherPeriods() throws {
        let source = try RecordingAssessmentTestSupport.decision(1, end: 86400)
        let automatic = try RecordingAssessmentTestSupport.decision(
            2,
            start: 100,
            end: 200,
            action: .automatic,
            predecessors: [source.id],
        )
        let ignore = try RecordingControlsTestSupport.ignore(10)
        let segments = try RecordingControlSelectionTestSupport.resolve([
            .source(automatic),
            .ignore(ignore),
            .source(source),
        ], end: 300)
        #expect(segments.count == 3)
        #expect(segments[0].resolution == .selected(source.author))
        guard case let .automatic(eligibility) = segments[1].resolution else {
            Issue.record("The historical interval must return to automatic.")
            return
        }
        #expect(eligibility.eligibility(of: source.author) == .ignored)
        #expect(eligibility.eligibility(of: RecordingControlsTestSupport.otherDevice) == .eligible)
        #expect(segments[2].resolution == .selected(source.author))
    }

    @Test func removalPreservesAnExclusiveChoiceAndOnlyItsLaterPortionNeedsReview() throws {
        let source = try RecordingAssessmentTestSupport.decision(1, end: 300)
        let removal = RecordingControlSelectionTestSupport.removal(at: 100)
        let earlier = RecordingControlSelectionTestSupport.removal(at: 80, identity: 101)
        let segments = try RecordingControlSelectionTestSupport.resolve(
            [.source(source)],
            removals: [removal, earlier, removal],
            end: 300,
        )
        #expect(segments.count == 2)
        #expect(segments[0].resolution == .selected(source.author))
        #expect(segments[1].period.start == earlier.removedAt)
        #expect(segments[1].resolution == .unresolved(.selectedDeviceRemoved(source.author)))
        #expect(segments.allSatisfy { $0.sourceChoiceIDs == [source.id] })
        #expect(try RecordingControlSelectionTestSupport.resolve(
            [.source(source)],
            removals: [earlier, removal],
            end: 300,
        ) == segments)
    }

    @Test func removalAlsoWinsOverAnIncompleteAutomaticEligibilityEdit() throws {
        let missingID = RecordingIgnoreDecision
            .ID(rawValue: RecordingAssessmentTestSupport.decisionID(11).rawValue)
        let ignore = try RecordingControlsTestSupport.ignore(10, predecessors: [missingID])
        let segments = try RecordingControlSelectionTestSupport.resolve(
            [.ignore(ignore)],
            removals: [RecordingControlSelectionTestSupport.removal(at: 100)],
            end: 200,
        )
        guard case let .automatic(before) = segments[0].resolution,
              case let .automatic(after) = segments[1].resolution
        else {
            Issue.record("Automatic controls retain per-device eligibility.")
            return
        }
        #expect(before.eligibility(of: ignore.deviceID) == .incomplete([missingID]))
        #expect(after.eligibility(of: ignore.deviceID) == .removed)
    }

    @Test func incompatibleSourceChoicesStayUnresolvedEvenWhenOneDeviceIsIgnored() throws {
        let first = try RecordingAssessmentTestSupport.decision(1, end: 300)
        let second = try RecordingAssessmentTestSupport.decision(
            2,
            start: 100,
            end: 200,
            action: .select(RecordingControlsTestSupport.otherDevice),
        )
        let segments = try RecordingControlSelectionTestSupport.resolve([
            .source(first),
            .source(second),
            .ignore(RecordingControlsTestSupport.ignore(10)),
        ], end: 300)
        #expect(segments.map(\.resolution) == [
            .selected(first.author),
            .unresolved(.sourceConflict([first.id, second.id])),
            .selected(first.author),
        ])
    }

    @Test func missingSourceDependenciesDoNotSilentlyReturnToAutomatic() throws {
        let first = try RecordingAssessmentTestSupport.decision(1)
        let automatic = try RecordingAssessmentTestSupport.decision(
            2,
            action: .automatic,
            predecessors: [first.id],
        )
        let segments = try RecordingControlSelectionTestSupport.resolve(
            [.source(automatic)],
            end: 100,
        )
        #expect(segments
            .allSatisfy { $0.resolution == .unresolved(.missingSourceChoices([first.id])) })
    }

    @Test func aSourceChoiceCannotResolveAnOpaqueControlAndItsScopeStaysBounded() throws {
        let source = try RecordingAssessmentTestSupport.decision(1, end: 300)
        let unknown = try VersionedHistoryRecord(
            id: .init(rawValue: UUID()),
            dataGenerationID: .initial,
            semantics: .init(major: 1, minor: 1, patch: 0),
            scope: .periods([RecordingAssessmentTestSupport.period(100, 200)]),
            kind: "recording.future-control",
            payload: Data([1, 2, 3]),
        )
        let controls = try RecordingControlSnapshot(
            records: [
                RecordingControlCodec.encode(.source(source), generationID: .initial),
                unknown,
            ],
            generationID: .initial,
            policy: RecordingChoiceTestSupport.policy,
        )
        let segments = try RecordingControlSelection.resolve(
            controls: controls,
            removals: [],
            within: RecordingAssessmentTestSupport.period(0, 300),
            version: RecordingEvidencePolicy.version,
        )
        #expect(segments.map(\.resolution) == [
            .selected(source.author),
            .unresolved(.unknownControls([unknown.id])),
            .selected(source.author),
        ])
        #expect(controls.requiresReview == [unknown])
    }

    @Test func malformedOrConflictingRemovalsFailBeforeSelection() throws {
        let removal = RecordingControlSelectionTestSupport.removal(at: 100)
        let conflict = RecordingControlSelectionTestSupport.removal(at: 200)
        #expect(throws: RecordingControlSelection.ValidationError.self) {
            try RecordingControlSelectionTestSupport.resolve([], removals: [removal, conflict])
        }
        #expect(throws: RecordingControlSelection.ValidationError.self) {
            try RecordingControlSelectionTestSupport.resolve(
                [],
                removals: [RecordingControlSelectionTestSupport.removal(at: .infinity)],
            )
        }
    }
}
