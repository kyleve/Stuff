import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingControlEditCoordinatorTests {
    @Test(arguments: RecordingControlEditTestSupport.Kind.allCases)
    func invalidRequestDoesNotRevokeAdmittedHistory(
        kind: RecordingControlEditTestSupport.Kind,
    ) async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let access = DataCompatibilityAccess(
            base: store,
            requiredMajor: 1,
            policy: RecordingChoiceTestSupport.policy,
            onFailure: { _, _ in },
        )
        let coordinator = RecordingControlEditTestSupport.coordinator(store: access.store)
        let invalid: RecordingControlEdit = switch kind {
            case .ignore:
                .ignore(
                    deviceID: RecordingChoiceTestSupport.author,
                    periods: [],
                    change: .restoreEligibility,
                )
            case .place:
                .place(placeID: RecordingControlsTestSupport.placeID, periods: [], action: .remove)
            case .calendar:
                .calendar(
                    deviceID: RecordingChoiceTestSupport.author,
                    periods: [],
                    action: .withdraw,
                )
        }
        await #expect(throws: DataCompatibilityError.incompleteRecord) {
            try await coordinator.review(invalid)
        }
        #expect(!access.isRevoked)
        try access.validate()
        _ = try await coordinator.review(RecordingControlEditTestSupport.edit(kind, removes: false))
        #expect(try await store.versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
            .isEmpty)
    }

    @Test(arguments: RecordingControlEditTestSupport.Kind.allCases)
    func editsKeepTypedCausalPredecessorsAndRetryWithoutNewOperations(
        kind: RecordingControlEditTestSupport
            .Kind,
    ) async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let original = try await coordinator.review(RecordingControlEditTestSupport.edit(
            kind,
            removes: false,
        ))
        #expect(try await coordinator.apply(original) == .applied)
        let removed = try await coordinator.review(RecordingControlEditTestSupport.edit(
            kind,
            removes: true,
        ))
        #expect(removed.control.predecessorRecordIDs == [original.control.recordID])
        #expect(try await coordinator.apply(removed) == .applied)
        #expect(try await coordinator.apply(removed) == .applied)
        let snapshot = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        #expect(snapshot.records.count == 2)
    }

    @Test(arguments: RecordingControlEditTestSupport.Kind.allCases)
    func aConcurrentControlRequiresARefreshedReview(kind: RecordingControlEditTestSupport
        .Kind) async throws
    {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let proposal = try await coordinator.review(RecordingControlEditTestSupport.edit(
            kind,
            removes: false,
        ))
        let other = try await coordinator.review(RecordingControlEditTestSupport.edit(
            kind,
            removes: true,
        ))
        #expect(try await coordinator.apply(other) == .applied)
        guard case let .stale(fresh) = try await coordinator.apply(proposal) else {
            Issue.record("A concurrent edit must not become an unreviewed predecessor.")
            return
        }
        #expect(fresh.control.recordID != proposal.control.recordID)
        #expect(fresh.control.predecessorRecordIDs == [other.control.recordID])
        let records = try await store
            .versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
        #expect(!records.contains { $0.id == proposal.control.recordID })
    }

    @Test func resumeAndUndoPreserveTheirSeparateHistoricalScopes() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let ignored = try await coordinator.review(RecordingControlEditTestSupport.edit(
            .ignore,
            removes: false,
        ))
        #expect(try await coordinator.apply(ignored) == .applied)
        let resume = try await coordinator.review(.ignore(
            deviceID: RecordingChoiceTestSupport.author,
            periods: [RecordingAssessmentTestSupport.period(400, 86400)],
            change: .restoreEligibility,
        ))
        #expect(try await coordinator.apply(resume) == .applied)
        let snapshot = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        let segments = try RecordingIgnoreResolver.resolve(
            snapshot.ignores,
            for: RecordingChoiceTestSupport.author,
            within: RecordingAssessmentTestSupport.period(0, 800),
            version: RecordingEvidencePolicy.version,
        )
        #expect(segments.map(\.resolution) == [.ignored, .eligible])
        #expect(try segments.map(\.period) == [
            RecordingAssessmentTestSupport.period(0, 400),
            RecordingAssessmentTestSupport.period(400, 800),
        ])
        let undo = try await coordinator.review(.ignore(
            deviceID: RecordingChoiceTestSupport.author,
            periods: [RecordingAssessmentTestSupport.period(0, 400)],
            change: .restoreEligibility,
        ))
        #expect(try await coordinator.apply(undo) == .applied)
        let complete = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        #expect(complete.ignores.count == 3)
        let restored = try RecordingIgnoreResolver.resolve(
            complete.ignores,
            for: RecordingChoiceTestSupport.author,
            within: RecordingAssessmentTestSupport.period(0, 800),
            version: RecordingEvidencePolicy.version,
        )
        #expect(restored.allSatisfy { $0.resolution == .eligible })
    }

    @Test func calendarRecoveryCannotOverrideAnAlreadyRecordedOffset() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let sample = try RecordingChoiceTestSupport.sample(seconds: 50)
        try await store.perform { try await store.add(sample: sample) }
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let conflicting = try RecordingControlEdit.calendar(
            deviceID: RecordingChoiceTestSupport.author,
            periods: [RecordingAssessmentTestSupport.period(0, 100)],
            action: .establish(.init(
                timeZone: #require(TimeZone(secondsFromGMT: 3600)),
                secondsFromGMT: 3600,
            )),
        )
        await #expect(throws: RecordingCalendarContext.ValidationError.conflictingRecordedContext) {
            try await coordinator.review(conflicting)
        }
        #expect(try await store.allSamples() == [sample])
    }

    @Test func aLateKnownContextInvalidatesCalendarRecoveryBeforeItCanWrite() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let edit = try RecordingControlEdit.calendar(
            deviceID: RecordingChoiceTestSupport.author,
            periods: [RecordingAssessmentTestSupport.period(0, 100)],
            action: .establish(.init(
                timeZone: #require(TimeZone(secondsFromGMT: 3600)),
                secondsFromGMT: 3600,
            )),
        )
        let proposal = try await coordinator.review(edit)
        let sample = try RecordingChoiceTestSupport.sample(seconds: 50)
        try await store.perform { try await store.add(sample: sample) }
        await #expect(throws: RecordingCalendarContext.ValidationError.conflictingRecordedContext) {
            try await coordinator.apply(proposal)
        }
        let controls = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        #expect(controls.records.isEmpty)
        #expect(try await store.allSamples() == [sample])
        #expect(proposal.evidence.samples.isEmpty)
        #expect(proposal.edit == edit)
    }

    @Test func changingAnIgnoreEndRestoresItsOldTailInOneDurableOperation() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let longEnd = try RecordingIgnoreDecision.Until(
            day: .init(year: 2001, month: 1, day: 3),
            timeZone: .gmt,
        )
        let original = try await coordinator.review(.ignore(
            deviceID: RecordingChoiceTestSupport.author,
            periods: [.init(start: .init(timeIntervalSinceReferenceDate: 0), end: longEnd.end)],
            change: .ignore(longEnd),
        ))
        #expect(try await coordinator.apply(original) == .applied)
        guard case let .ignore(originalDecision) = original.control else {
            Issue.record("Expected the reviewed ignore.")
            return
        }
        let shortEnd = try RecordingIgnoreDecision.Until(
            day: .init(year: 2001, month: 1, day: 1),
            timeZone: .gmt,
        )
        let shortened = try await coordinator.review(.changingIgnoreEnd(
            of: originalDecision,
            until: shortEnd,
        ))
        #expect(shortened.control.predecessorRecordIDs == [original.control.recordID])
        #expect(try await coordinator.apply(shortened) == .applied)
        #expect(try await coordinator.apply(shortened) == .applied)
        let snapshot = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        #expect(snapshot.ignores.count == 2)
        let changed = try #require(snapshot.ignores.first { $0.id != originalDecision.id })
        #expect(changed.change == .ignore(shortEnd))
        let segments = try RecordingIgnoreResolver.resolve(
            snapshot.ignores.reversed(),
            for: RecordingChoiceTestSupport.author,
            within: RecordingAssessmentTestSupport.period(0, 3 * 86400),
            version: RecordingEvidencePolicy.version,
        )
        #expect(segments.map(\.resolution) == [.ignored, .eligible])
        #expect(try segments.map(\.period) == [
            RecordingAssessmentTestSupport.period(0, 86400),
            RecordingAssessmentTestSupport.period(86400, 3 * 86400),
        ])

        let extended = try await coordinator.review(.changingIgnoreEnd(of: changed, until: longEnd))
        #expect(try await coordinator.apply(extended) == .applied)
        let final = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        let restored = try RecordingIgnoreResolver.resolve(
            final.ignores,
            for: RecordingChoiceTestSupport.author,
            within: RecordingAssessmentTestSupport.period(0, 3 * 86400),
            version: RecordingEvidencePolicy.version,
        )
        #expect(restored.allSatisfy { $0.resolution == .ignored })
    }

    @Test func aConcurrentExtensionRequiresANewPreviewOfTheWholeRestoredTail() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let originalEnd = try RecordingIgnoreDecision.Until(
            day: .init(year: 2001, month: 1, day: 3),
            timeZone: .gmt,
        )
        let original = try await coordinator.review(.ignore(
            deviceID: RecordingChoiceTestSupport.author,
            periods: [RecordingAssessmentTestSupport.period(0, 3 * 86400)],
            change: .ignore(originalEnd),
        ))
        #expect(try await coordinator.apply(original) == .applied)
        guard case let .ignore(decision) = original.control else {
            Issue.record("Expected an ignore decision.")
            return
        }
        let shortEnd = try RecordingIgnoreDecision.Until(
            day: .init(year: 2001, month: 1, day: 1),
            timeZone: .gmt,
        )
        let shortening = try await coordinator.review(.changingIgnoreEnd(
            of: decision,
            until: shortEnd,
        ))
        let longEnd = try RecordingIgnoreDecision.Until(
            day: .init(year: 2001, month: 1, day: 5),
            timeZone: .gmt,
        )
        let extensionEdit = try await coordinator.review(.changingIgnoreEnd(
            of: decision,
            until: longEnd,
        ))
        #expect(try await coordinator.apply(extensionEdit) == .applied)
        guard case let .stale(fresh) = try await coordinator.apply(shortening) else {
            Issue.record("An extension needs a new review before shortening its added tail.")
            return
        }
        #expect(try shortening.evidence.query.periods == [RecordingAssessmentTestSupport.period(
            0,
            3 * 86400,
        )])
        #expect(try fresh.evidence.query.periods == [RecordingAssessmentTestSupport.period(
            0,
            5 * 86400,
        )])
        #expect(fresh.control.predecessorRecordIDs.contains(extensionEdit.control.recordID))
        let before = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        #expect(!before.records
            .contains { $0.id == shortening.control.recordID || $0.id == fresh.control.recordID })
        #expect(try await coordinator.apply(fresh) == .applied)
        let after = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        let segments = try RecordingIgnoreResolver.resolve(
            after.ignores,
            for: RecordingChoiceTestSupport.author,
            within: RecordingAssessmentTestSupport.period(0, 5 * 86400),
            version: RecordingEvidencePolicy.version,
        )
        #expect(segments.first?.resolution == .ignored)
        #expect(segments.dropFirst().allSatisfy { $0.resolution == .eligible })
    }
}
