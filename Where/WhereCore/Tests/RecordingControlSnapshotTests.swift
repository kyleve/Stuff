import Testing
@testable import WhereCore

struct RecordingControlSnapshotTests {
    @Test func aKnownOtherFamilyIsInvalidRatherThanPermanentlyMissing() throws {
        let predecessorUUID = RecordingAssessmentTestSupport.decisionID(1).rawValue
        let pairs: [[RecordingControl]] = try [
            [
                .ignore(RecordingControlsTestSupport.ignore(1)),
                .source(RecordingAssessmentTestSupport.decision(
                    2,
                    predecessors: [.init(rawValue: predecessorUUID)],
                )),
            ],
            [
                .source(RecordingAssessmentTestSupport.decision(1)),
                .ignore(RecordingControlsTestSupport.ignore(
                    2,
                    predecessors: [.init(rawValue: predecessorUUID)],
                )),
            ],
            [
                .ignore(RecordingControlsTestSupport.ignore(1)),
                .place(RecordingControlsTestSupport.place(
                    2,
                    predecessors: [.init(rawValue: predecessorUUID)],
                )),
            ],
            [
                .place(RecordingControlsTestSupport.place(1)),
                .calendar(RecordingControlsTestSupport.calendar(
                    2,
                    action: .withdraw,
                    predecessors: [.init(rawValue: predecessorUUID)],
                )),
            ],
        ]
        for pair in pairs {
            let records = try pair
                .map { try RecordingControlCodec.encode($0, generationID: .initial) }
            #expect(throws: DataCompatibilityError.conflictingRecord) {
                try RecordingControlSnapshot(
                    records: records,
                    generationID: .initial,
                    policy: DataCompatibilityTestSupport.policy,
                )
            }
        }
    }

    @Test func allFamiliesRoundTripWithoutCollapsingDistinctIdentities() throws {
        let values: [RecordingControl] = try [
            .source(RecordingAssessmentTestSupport.decision(1)),
            .ignore(RecordingControlsTestSupport.ignore(2)),
            .place(RecordingControlsTestSupport.place(3)),
            .calendar(RecordingControlsTestSupport.calendar(
                4,
                action: .withdraw,
            )),
        ]
        let records = try values
            .map { try RecordingControlCodec.encode($0, generationID: .initial) }
        let snapshot = try RecordingControlSnapshot(
            records: records.reversed() + records,
            generationID: .initial,
            policy: DataCompatibilityTestSupport.policy,
        )
        #expect(snapshot.sourceChoices.count == 1)
        #expect(snapshot.ignores.count == 1)
        #expect(snapshot.places.count == 1)
        #expect(snapshot.calendarContexts.count == 1)
        #expect(snapshot.records == records)
        #expect(snapshot.requiresReview.isEmpty)
    }

    @Test func partialDependencyDeliveryRemainsValidButACompletedCycleIsRejected() throws {
        let first = try RecordingAssessmentTestSupport.decision(
            1,
            predecessors: [RecordingAssessmentTestSupport.decisionID(2)],
        )
        let second = try RecordingAssessmentTestSupport.decision(2, predecessors: [first.id])
        let firstRecord = try RecordingControlCodec.encode(.source(first), generationID: .initial)
        let secondRecord = try RecordingControlCodec.encode(.source(second), generationID: .initial)
        let partial = try RecordingControlSnapshot(
            records: [firstRecord],
            generationID: .initial,
            policy: DataCompatibilityTestSupport.policy,
        )
        #expect(try HistoryDecisionResolver.resolve(
            partial.sourceChoices,
            within: RecordingAssessmentTestSupport.period(0, 100),
            version: first.version,
        ).first?.resolution == .incomplete([second.id]))
        #expect(throws: HistoryDecisionResolver.ValidationError.self) {
            try RecordingControlSnapshot(
                records: [secondRecord, firstRecord],
                generationID: .initial,
                policy: DataCompatibilityTestSupport.policy,
            )
        }
    }

    @Test func aReusedUUIDCannotChangeControlFamily() throws {
        let records = try [
            RecordingControlCodec.encode(
                .source(RecordingAssessmentTestSupport.decision(1)),
                generationID: .initial,
            ),
            RecordingControlCodec.encode(
                .ignore(RecordingControlsTestSupport.ignore(1)),
                generationID: .initial,
            ),
        ]
        #expect(throws: DataCompatibilityError.conflictingRecord) {
            try RecordingControlSnapshot(
                records: records,
                generationID: .initial,
                policy: DataCompatibilityTestSupport.policy,
            )
        }
    }
}

extension RecordingControlSnapshotTests {
    @Test func observationPredecessorsAreInvalidBeforeControlPayloadsAreFiltered() throws {
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let observation = try VersionedLocationSample.encode(sample, generationID: .initial)
        let decision = try RecordingAssessmentTestSupport.decision(
            16,
            predecessors: [.init(rawValue: sample.id)],
        )
        let control = try RecordingControlCodec.encode(.source(decision), generationID: .initial)
        let policy = RecordingBackupTestSupport.policy
        #expect(try RecordingControlSnapshot(
            records: [control],
            generationID: .initial,
            policy: policy,
        ).sourceChoices == [decision])
        for records in [[control, observation], [observation, control]] {
            #expect(throws: DataCompatibilityError.conflictingRecord) {
                try RecordingControlSnapshot(
                    records: records,
                    generationID: .initial,
                    policy: policy,
                )
            }
        }
    }
}
