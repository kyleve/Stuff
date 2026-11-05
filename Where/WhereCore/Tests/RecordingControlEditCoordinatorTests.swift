import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingControlEditCoordinatorTests {
    @Test func historyReadRequiresAnActiveRecordingContractAndCurrentAccess() async throws {
        let legacy = try SwiftDataStore.inMemory()
        let inactive = RecordingControlEditTestSupport.coordinator(store: legacy)
        await #expect(throws: DataCompatibilityError.activationNotReady) {
            try await inactive.ignoreHistory(for: RecordingControlsTestSupport.device)
        }
        await #expect(throws: DataCompatibilityError.activationNotReady) {
            try await inactive.placeHistory()
        }
        let store = try await RecordingChoiceTestSupport.store()
        let access = DataCompatibilityAccess(
            base: store,
            requiredMajor: 1,
            policy: RecordingChoiceTestSupport.policy,
            onFailure: { _, _ in },
        )
        let coordinator = RecordingControlEditTestSupport.coordinator(store: access.store)
        let initial = try await coordinator.ignoreHistory(for: RecordingControlsTestSupport.device)
        #expect(initial.decisions.isEmpty)
        #expect(try await initial.generationID == (store.dataGeneration().id))
        let places = try await coordinator.placeHistory()
        #expect(places.entries.isEmpty)
        #expect(places.generationID == initial.generationID)
        access.revoke()
        await #expect(throws: (any Error).self) {
            try await coordinator.ignoreHistory(for: RecordingControlsTestSupport.device)
        }
        await #expect(throws: (any Error).self) {
            try await coordinator.placeHistory()
        }
    }

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
                .place(placeID: RecordingControlsTestSupport.placeID, validity: [], action: .remove)
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
        #expect(try (RecordingControlEditTestSupport.control(removed))
            .predecessorRecordIDs ==
            [(RecordingControlEditTestSupport.control(original)).recordID])
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
        #expect(try (RecordingControlEditTestSupport.control(fresh))
            .recordID != (RecordingControlEditTestSupport.control(proposal)).recordID)
        #expect(try (RecordingControlEditTestSupport.control(fresh))
            .predecessorRecordIDs ==
            [(RecordingControlEditTestSupport.control(other)).recordID])
        let records = try await store
            .versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
        let proposalRecordID = try RecordingControlEditTestSupport.control(proposal).recordID
        #expect(!records
            .contains { $0.id == proposalRecordID })
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
        #expect(proposal.edits.map(\.edit) == [edit])
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
        guard case let .ignore(originalDecision) = try (RecordingControlEditTestSupport
            .control(original))
        else {
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
        #expect(try (RecordingControlEditTestSupport.control(shortened))
            .predecessorRecordIDs ==
            [(RecordingControlEditTestSupport.control(original)).recordID])
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
        guard case let .ignore(decision) = try (RecordingControlEditTestSupport.control(original))
        else {
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
        #expect(try (RecordingControlEditTestSupport.control(fresh)).predecessorRecordIDs
            .contains((RecordingControlEditTestSupport.control(extensionEdit)).recordID))
        let before = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        let shorteningRecordID = try RecordingControlEditTestSupport.control(shortening).recordID
        let freshRecordID = try RecordingControlEditTestSupport.control(fresh).recordID
        #expect(!before.records
            .contains {
                $0.id == shorteningRecordID || $0.id == freshRecordID
            })
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

    @Test(arguments: [false, true])
    func resumeReviewsExtensionsWithoutRestoringElapsedOrUnrelatedHistory(
        extensionBeforePreview: Bool,
    ) async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let decision = try RecordingControlsTestSupport.ignore(61)
        try await RecordingChoiceTestSupport.append(.ignore(decision), store: store)
        let until = try RecordingIgnoreDecision.Until(
            day: .init(year: 2001, month: 1, day: 3),
            timeZone: .gmt,
        )
        let extended = try await coordinator.review(.changingIgnoreEnd(of: decision, until: until))
        let later = try RecordingControlsTestSupport.ignore(
            62,
            start: 5 * 86400,
            end: 6 * 86400,
            change: .ignore(.init(day: .init(year: 2001, month: 1, day: 6), timeZone: .gmt)),
            predecessors: [decision.id],
        )
        try await RecordingChoiceTestSupport.append(.ignore(later), store: store)
        if extensionBeforePreview { #expect(try await coordinator.apply(extended) == .applied) }
        let resume = try await coordinator.review(.resumingIgnore(
            decision,
            at: .init(timeIntervalSinceReferenceDate: 600),
        ))
        let reviewed: RecordingControlEditCoordinator.Proposal
        if extensionBeforePreview {
            reviewed = resume
        } else {
            #expect(try await coordinator.apply(extended) == .applied)
            guard case let .stale(fresh) = try await coordinator.apply(resume) else {
                Issue
                    .record("Resume must show the extension before changing its additional period.")
                return
            }
            #expect(try resume.evidence.query.periods == [RecordingAssessmentTestSupport.period(
                600,
                86400,
            )])
            let before = try await coordinator.ignoreHistory(for: decision.deviceID)
            #expect(!before.decisions.contains { $0.change == .restoreEligibility })
            reviewed = fresh
        }
        #expect(try reviewed.evidence.query.periods == [RecordingAssessmentTestSupport.period(
            600,
            3 * 86400,
        )])
        #expect(try await coordinator.apply(reviewed) == .applied)
        #expect(try await coordinator.apply(reviewed) == .applied)
        let history = try await coordinator.ignoreHistory(for: decision.deviceID)
        #expect(history.decisions.count == 4)
        #expect(history.segments.first?.period.end == Date(timeIntervalSinceReferenceDate: 600))
        #expect(history.segments.first?.resolution == .ignored)
        #expect(history.segments.last?.period == later.periods.first)
        #expect(history.segments.last?.resolution == .ignored)
        #expect(history.segments.dropFirst().dropLast().allSatisfy { $0.resolution == .eligible })
        let inspection = try coordinator.inspectIgnore(reviewed)
        #expect(inspection.changes.allSatisfy { $0.after == .automatic(.eligible) })
    }

    @Test func resumeDoesNotAdoptAShortenedIgnoresRestoredTail() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let original = try RecordingControlsTestSupport.ignore(
            71,
            end: 10 * 86400,
            change: .ignore(.init(day: .init(year: 2001, month: 1, day: 10), timeZone: .gmt)),
        )
        let shortened = try RecordingControlsTestSupport.ignore(
            72,
            end: 10 * 86400,
            change: .ignore(.init(day: .init(year: 2001, month: 1, day: 5), timeZone: .gmt)),
            predecessors: [original.id],
        )
        let separate = try RecordingControlsTestSupport.ignore(
            73,
            start: 8 * 86400,
            end: 9 * 86400,
            change: .ignore(.init(day: .init(year: 2001, month: 1, day: 9), timeZone: .gmt)),
            predecessors: [shortened.id],
        )
        for decision in [original, shortened, separate] {
            try await RecordingChoiceTestSupport.append(.ignore(decision), store: store)
        }
        let intent = try RecordingControlEdit.resumingIgnore(
            shortened,
            at: .init(timeIntervalSinceReferenceDate: 2 * 86400),
        )
        let preview = try await coordinator.review(intent)
        #expect(try preview.evidence.query.periods == [RecordingAssessmentTestSupport.period(
            2 * 86400,
            5 * 86400,
        )])
        let extended = try RecordingControlsTestSupport.ignore(
            74,
            end: 10 * 86400,
            change: .ignore(.init(day: .init(year: 2001, month: 1, day: 6), timeZone: .gmt)),
            predecessors: [shortened.id],
        )
        try await RecordingChoiceTestSupport.append(.ignore(extended), store: store)
        guard case let .stale(refreshed) = try await coordinator.apply(preview) else {
            Issue.record("A changed end requires a fresh resume preview."); return
        }
        #expect(try refreshed.evidence.query.periods == [RecordingAssessmentTestSupport.period(
            2 * 86400,
            6 * 86400,
        )])
        let before = try await coordinator.ignoreHistory(for: original.deviceID)
        let retained = try #require(before.segments.first {
            $0.period.contains(.init(timeIntervalSinceReferenceDate: 8.5 * 86400))
        })
        // The concurrent extension restores the later tail, while the separate choice ignores
        // it. Resume must preserve that existing conflict outside its reviewed ignored portion.
        #expect(retained.resolution == .conflict([separate.id, extended.id]))
        #expect(try await coordinator.apply(refreshed) == .applied)
        let history = try await coordinator.ignoreHistory(for: original.deviceID)
        let later = try #require(history.segments
            .first { $0.period.contains(.init(timeIntervalSinceReferenceDate: 8.5 * 86400)) })
        #expect(later == retained)
    }

    @Test func disjointCalendarEditsCommitAndRetryAsOneReviewedBatch() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let edits: [RecordingControlEdit] = try [
            .calendar(
                deviceID: RecordingChoiceTestSupport.author,
                periods: [RecordingAssessmentTestSupport.period(0, 100)],
                action: .establish(.init(timeZone: .gmt, secondsFromGMT: 0)),
            ),
            .calendar(
                deviceID: RecordingChoiceTestSupport.author,
                periods: [RecordingAssessmentTestSupport.period(200, 300)],
                action: .establish(.init(timeZone: .gmt, secondsFromGMT: 0)),
            ),
        ]
        let proposal = try await coordinator.review(edits)
        #expect(proposal.edits.map(\.edit) == edits)
        #expect(try proposal.evidence.query.periods == [
            RecordingAssessmentTestSupport.period(0, 100),
            RecordingAssessmentTestSupport.period(200, 300),
        ])
        #expect(try await coordinator.apply(proposal) == .applied)
        let records = try await store
            .versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
        #expect(Set(records.map(\.id)) == Set(proposal.edits.map(\.control.recordID)))
        #expect(records.count == 2)
        #expect(try await coordinator.apply(proposal) == .applied)
        #expect(try await Set(store
                .versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)) ==
            Set(records))
        let controls = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        let segments = try RecordingCalendarResolver.resolve(
            controls.calendarContexts,
            for: RecordingChoiceTestSupport.author,
            within: RecordingAssessmentTestSupport.period(0, 300),
            version: RecordingEvidencePolicy.version,
        )
        #expect(try segments.map(\.period) == [
            RecordingAssessmentTestSupport.period(0, 100),
            RecordingAssessmentTestSupport.period(100, 200),
            RecordingAssessmentTestSupport.period(200, 300),
        ])
        #expect(segments[1].resolution == .unknown)
    }

    @Test func overlappingBatchScopesAreRejectedBeforeAdmittedReads() async throws {
        let base = try await RecordingChoiceTestSupport.store()
        let access = DataCompatibilityAccess(
            base: base,
            requiredMajor: 1,
            policy: RecordingChoiceTestSupport.policy,
            onFailure: { _, _ in },
        )
        let coordinator = RecordingControlEditTestSupport.coordinator(store: access.store)
        let edit = try RecordingControlEditTestSupport.edit(.calendar, removes: false)
        await #expect(throws: RecordingControlEditCoordinator.ValidationError.overlappingEdits) {
            try await coordinator.review([edit, edit])
        }
        await #expect(throws: DataCompatibilityError.incompleteRecord) {
            try await coordinator.review([])
        }
        #expect(access.isRevoked == false)
        #expect(try await base.versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
            .isEmpty)
        let independent = try await coordinator.review([
            edit,
            RecordingControlEditTestSupport.edit(.place, removes: false),
        ])
        #expect(independent.edits.count == 2)
        #expect(try await coordinator.apply(independent) == .applied)
    }

    @Test func aLateKnownOffsetRejectsTheEntireCalendarBatch() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let proposal = try await coordinator.review([
            .calendar(
                deviceID: RecordingChoiceTestSupport.author,
                periods: [RecordingAssessmentTestSupport.period(0, 100)],
                action: .establish(.init(timeZone: .gmt, secondsFromGMT: 0)),
            ),
            .calendar(
                deviceID: RecordingChoiceTestSupport.author,
                periods: [RecordingAssessmentTestSupport.period(100, 200)],
                action: .establish(.init(timeZone: .gmt, secondsFromGMT: 3600)),
            ),
        ])
        let sample = try RecordingChoiceTestSupport.sample(seconds: 150)
        try await store.perform { try await store.add(sample: sample) }
        await #expect(throws: RecordingCalendarContext.ValidationError.conflictingRecordedContext) {
            try await coordinator.apply(proposal)
        }
        let snapshot = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        #expect(snapshot.calendarContexts.isEmpty)
        #expect(try await store.allSamples() == [sample])
    }

    @Test func partialRemoteDeliveryRequiresAReviewBeforeWritingRemainingSegments() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let recovery = try RecordingCalendarRecovery(
            deviceID: RecordingChoiceTestSupport.author,
            periods: [
                RecordingAssessmentTestSupport.period(0, 100),
                RecordingAssessmentTestSupport.period(200, 300),
            ],
            timeZone: .gmt,
        )
        let proposal = try await coordinator.review(recovery.edits)
        let delivered = try #require(proposal.edits.first?.control)
        try await RecordingChoiceTestSupport.append(delivered, store: store)
        guard case let .stale(fresh) = try await coordinator.apply(proposal) else {
            Issue.record("A partial remote batch must not finish without fresh review.")
            return
        }
        let records = try await store
            .versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
        #expect(records.map(\.id) == [delivered.recordID])
        #expect(fresh.edits.map(\.edit) == recovery.edits)
        #expect(fresh.edits.first?.control.predecessorRecordIDs == [delivered.recordID])
        #expect(try await coordinator.apply(fresh) == .applied)
        #expect(try await store.versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
            .count == 3)
    }

    @Test func aBatchIdentityCollisionCannotSaveItsEarlierEntries() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let recovery = try RecordingControlEditTestSupport.calendarRecovery()
        let proposal = try await coordinator.review(recovery.edits)
        guard case let .calendar(original) = try #require(proposal.edits.last?.control) else {
            Issue.record("Expected the calendar batch.")
            return
        }
        let conflicting = try RecordingCalendarDecision(
            id: original.id,
            author: original.author,
            deviceID: original.deviceID,
            periods: original.periods,
            action: .withdraw,
            predecessors: original.predecessors,
            version: original.version,
        )
        try await RecordingChoiceTestSupport.append(.calendar(conflicting), store: store)
        await #expect(throws: DataCompatibilityError.conflictingRecord) {
            try await coordinator.apply(proposal)
        }
        let snapshot = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        #expect(snapshot.calendarContexts == [conflicting])
    }

    @Test func resetAndServiceReplacementRetireTheWholeBatch() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let proposal = try await coordinator
            .review(RecordingControlEditTestSupport.calendarRecovery().edits)
        let replacement = RecordingControlEditTestSupport.coordinator(store: store)
        guard case let .stale(rebound) = try await replacement.apply(proposal) else {
            Issue.record("Another service requires its own review.")
            return
        }
        #expect(Set(rebound.edits.map(\.control.recordID))
            .isDisjoint(with: proposal.edits.map(\.control.recordID)))
        try await store.perform {
            _ = try await store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: RecordingChoiceTestSupport.author,
                at: RecordingAssessmentTestSupport.time(400),
            )
        }
        guard case let .stale(fresh) = try await coordinator.apply(proposal) else {
            Issue.record("Reset requires a new review without saving any old operation.")
            return
        }
        #expect(fresh.evidence.generationID != proposal.evidence.generationID)
        #expect(Set(fresh.edits.map(\.control.recordID))
            .isDisjoint(with: proposal.edits.map(\.control.recordID)))
        #expect(try await store.versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
            .isEmpty)
    }
}
