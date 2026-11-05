import Foundation
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingChoiceCoordinatorTests {
    @Test func theFoundationContractCannotAuthorRecordingChoices() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = RecordingChoiceCoordinator(
            store: store,
            policy: .foundation,
            author: RecordingChoiceTestSupport.author,
            onCommitted: {},
        )
        await #expect(throws: DataCompatibilityError.activationNotReady) {
            try await coordinator.review(RecordingChoiceTestSupport.request())
        }
    }

    @Test func compatibleMinorAndPatchDecisionsRemainExplicitPredecessors() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let prior = try RecordingAssessmentTestSupport.decision(
            29,
            version: .init(major: 1, minor: 8, patch: 3),
        )
        try await RecordingChoiceTestSupport.append(.source(prior), store: store)
        let coordinator = RecordingChoiceTestSupport.coordinator(store: store)
        let proposal = try await RecordingChoiceTestSupport.proposal(coordinator.review(
            RecordingChoiceTestSupport.request(),
        ))
        #expect(proposal.decision.predecessors == [prior.id])
        #expect(proposal.decision.version == RecordingEvidencePolicy.version)
        #expect(try await coordinator.apply(proposal) == .applied)
    }

    @Test func retriesKeepTheCommittedOperationWithoutAdoptingLaterDecisions() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let original = try RecordingAssessmentTestSupport.decision(30)
        try await RecordingChoiceTestSupport.append(.source(original), store: store)
        let coordinator = RecordingChoiceTestSupport.coordinator(store: store)
        let proposal = try await RecordingChoiceTestSupport.proposal(coordinator.review(
            RecordingChoiceTestSupport.request(),
        ))
        #expect(proposal.decision.predecessors == [original.id])
        #expect(try await coordinator.apply(proposal) == .applied)
        let concurrent = try RecordingAssessmentTestSupport.decision(
            31,
            action: .select(RecordingControlsTestSupport.otherDevice),
        )
        try await RecordingChoiceTestSupport.append(.source(concurrent), store: store)
        #expect(try await coordinator.apply(proposal) == .applied)
        let snapshot = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        #expect(snapshot.sourceChoices.count == 3)
        #expect(snapshot.sourceChoices.contains(proposal.decision))
        let segments = try HistoryDecisionResolver.resolve(
            snapshot.sourceChoices,
            within: RecordingAssessmentTestSupport.period(0, 100),
            version: RecordingEvidencePolicy.version,
        )
        #expect(segments.first?.resolution == .conflict([proposal.decision.id, concurrent.id]))
    }

    @Test func unrelatedImportsBeforeSaveDoNotRequireAnotherReview() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingChoiceTestSupport.coordinator(store: store)
        let proposal = try await RecordingChoiceTestSupport.proposal(coordinator.review(
            RecordingChoiceTestSupport.request(),
        ))
        try await store.perform {
            try await store.add(sample: RecordingChoiceTestSupport.sample(seconds: 10 * 86400))
        }
        try await RecordingChoiceTestSupport.append(.source(RecordingAssessmentTestSupport.decision(
            40,
            start: 10 * 86400,
            end: 11 * 86400,
        )), store: store)
        #expect(try await coordinator.apply(proposal) == .applied)
        #expect(proposal.decision.predecessors.isEmpty)
    }

    @Test(arguments: [false, true])
    func changedEvidenceOrDecisionReturnsANewReviewWithoutWriting(
        changesDecision: Bool,
    ) async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let commits = RecordingChoiceTestSupport.Commits()
        let coordinator = RecordingChoiceTestSupport.coordinator(store: store, commits: commits)
        let proposal = try await RecordingChoiceTestSupport.proposal(coordinator.review(
            RecordingChoiceTestSupport.request(),
        ))
        if changesDecision {
            try await RecordingChoiceTestSupport.append(
                .source(RecordingAssessmentTestSupport.decision(50)),
                store: store,
            )
        } else {
            try await store
                .perform {
                    try await store.add(sample: RecordingChoiceTestSupport.sample(seconds: 50))
                }
        }
        let result = try await coordinator.apply(proposal)
        guard case let .stale(.ready(refreshed)) = result else {
            Issue.record("Changed inputs must return a refreshed review.")
            return
        }
        #expect(refreshed.decision.id != proposal.decision.id)
        #expect(refreshed.evidence != proposal.evidence)
        let records = try await store
            .versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
        #expect(!records.contains { $0.id.rawValue == proposal.decision.id.rawValue })
        #expect(await commits.count == 0)
    }

    @Test(arguments: [false, true])
    func anImportDuringSaveRetriesOnlyWhenRelevantEvidenceStillMatches(relevant: Bool) async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        try await store.perform { try await store.raiseRequiredDataMajor(1) }
        let gate = CompatibilityTestGate()
        var configured = RecordingChoiceTestSupport.coordinator(store: store)
        configured.setBeforeWriteForTesting { await gate.suspend() }
        let coordinator = configured
        let proposal = try await RecordingChoiceTestSupport.proposal(coordinator.review(
            RecordingChoiceTestSupport.request(),
        ))
        let operation = Task { try await coordinator.apply(proposal) }
        await gate.waitUntilEntered()
        let remote = ModelContext(container)
        let row = SDVersionedHistoryRecord()
        row.envelope = try JSONEncoder().encode(RecordingControlCodec.encode(
            .source(RecordingAssessmentTestSupport.decision(
                60,
                start: relevant ? 0 : 86400,
                end: relevant ? 100 : 86500,
            )),
            generationID: .initial,
        ))
        remote.insert(row)
        try remote.save()
        await gate.resume()
        let result = try await operation.value
        if relevant {
            guard case let .stale(.ready(refreshed)) = result else {
                Issue.record("A relevant concurrent import must require new review.")
                return
            }
            #expect(refreshed.decision
                .predecessors == [RecordingAssessmentTestSupport.decisionID(60)])
        } else {
            #expect(result == .applied)
        }
        let choices = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        )
        .snapshot().sourceChoices
        #expect(choices.contains(proposal.decision) == !relevant)
        #expect(proposal.decision.predecessors.isEmpty)
    }

    @Test func aProposalCannotCrossAnAdmittedServiceScopeEvenWithTheSameInitialGeneration(
    ) async throws {
        let first = try await RecordingChoiceTestSupport.store()
        let second = try await RecordingChoiceTestSupport.store()
        let old = RecordingChoiceTestSupport.coordinator(store: first)
        let proposal = try await RecordingChoiceTestSupport
            .proposal(old.review(RecordingChoiceTestSupport.request()))
        let replacement = RecordingChoiceTestSupport.coordinator(store: second)
        guard case .stale = try await replacement.apply(proposal) else {
            Issue.record("A different scope must obtain its own review.")
            return
        }
        #expect(try await second.versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
            .isEmpty)
    }

    @Test func revokedCompatibilityCannotCommitAReviewedChoice() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let access = DataCompatibilityAccess(
            base: store,
            requiredMajor: 1,
            policy: RecordingChoiceTestSupport.policy,
            onFailure: { _, _ in },
        )
        let gate = CompatibilityTestGate()
        var configured = RecordingChoiceTestSupport.coordinator(store: access.store)
        configured.setBeforeWriteForTesting { await gate.suspend() }
        let coordinator = configured
        let proposal = try await RecordingChoiceTestSupport
            .proposal(coordinator.review(RecordingChoiceTestSupport.request()))
        let operation = Task { try await coordinator.apply(proposal) }
        await gate.waitUntilEntered()
        access.revoke()
        await gate.resume()
        await #expect(throws: DataAccessPermit.AccessError.revoked) { try await operation.value }
        #expect(try await store.versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
            .isEmpty)
    }

    @Test func resetRejectsTheOldProposalWithoutRebindingItsOperation() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingChoiceTestSupport.coordinator(store: store)
        let proposal = try await RecordingChoiceTestSupport
            .proposal(coordinator.review(RecordingChoiceTestSupport.request()))
        try await store.perform {
            _ = try await store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: RecordingChoiceTestSupport.author,
                at: Date(),
            )
        }
        guard case let .stale(.ready(fresh)) = try await coordinator.apply(proposal) else {
            Issue.record("Reset must return a review in the new data generation.")
            return
        }
        #expect(fresh.evidence.generationID != proposal.evidence.generationID)
        #expect(fresh.decision.id != proposal.decision.id)
        #expect(try await store.versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
            .isEmpty)
    }

    @Test func aWholeDayRequiresCompleteCalendarContextButNoGPS() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingChoiceTestSupport.coordinator(store: store)
        let day = CalendarDay(year: 2001, month: 1, day: 1)
        let request = RecordingChoiceRequest(
            scope: .recordingDay(deviceID: RecordingChoiceTestSupport.author, day: day),
            action: .select(RecordingChoiceTestSupport.author),
        )
        guard case let .needsCalendarContext(missing) = try await coordinator.review(request) else {
            Issue.record("Missing context must require clarification.")
            return
        }
        #expect(try missing.missingPeriods == [RecordingDayCoverage.searchPeriod(for: day)])
        let calendar = try RecordingCalendarDecision(
            id: .init(rawValue: UUID()),
            author: RecordingChoiceTestSupport.author,
            deviceID: RecordingChoiceTestSupport.author,
            periods: [RecordingDayCoverage.searchPeriod(for: day)],
            action: .establish(.init(timeZone: .gmt, secondsFromGMT: 0)),
            predecessors: [],
            version: RecordingEvidencePolicy.version,
        )
        try await RecordingChoiceTestSupport.append(.calendar(calendar), store: store)
        let proposal = try await RecordingChoiceTestSupport.proposal(coordinator.review(request))
        #expect(try proposal.decision.periods == [RecordingAssessmentTestSupport.period(0, 86400)])
        #expect(proposal.evidence.samples.isEmpty)
        #expect(try await coordinator.apply(proposal) == .applied)
    }

    @Test func repeatedLogicalDayChoicesRetainTheInterveningGap() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let day = CalendarDay(year: 2001, month: 1, day: 1)
        let search = try RecordingDayCoverage.searchPeriod(for: day)
        let transition = RecordingAssessmentTestSupport.time(30 * 3600)
        for context in try [
            RecordingDayCoverage.Context(
                period: RecordingPeriod(start: search.start, end: transition),
                calendarContext: .init(timeZone: .gmt, secondsFromGMT: 0),
            ),
            RecordingDayCoverage.Context(
                period: RecordingPeriod(start: transition, end: search.end),
                calendarContext: .init(
                    timeZone: #require(TimeZone(secondsFromGMT: -12 * 3600)),
                    secondsFromGMT: -12 * 3600,
                ),
            ),
        ] {
            try await RecordingChoiceTestSupport.append(.calendar(.init(
                id: .init(rawValue: UUID()),
                author: RecordingChoiceTestSupport.author,
                deviceID: RecordingChoiceTestSupport.author,
                periods: [context.period],
                action: .establish(context.calendarContext),
                predecessors: [],
                version: RecordingEvidencePolicy.version,
            )), store: store)
        }
        let coordinator = RecordingChoiceTestSupport.coordinator(store: store)
        let request = RecordingChoiceRequest(
            scope: .recordingDay(deviceID: RecordingChoiceTestSupport.author, day: day),
            action: .select(RecordingChoiceTestSupport.author),
        )
        let proposal = try await RecordingChoiceTestSupport.proposal(coordinator.review(request))
        #expect(try proposal.decision.periods == [
            RecordingAssessmentTestSupport.period(0, 24 * 3600),
            RecordingAssessmentTestSupport.period(30 * 3600, 36 * 3600),
        ])
        #expect(try await coordinator.apply(proposal) == .applied)
    }
}
