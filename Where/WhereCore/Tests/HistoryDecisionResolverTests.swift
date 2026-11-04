import Foundation
import Testing
@testable import WhereCore

struct HistoryDecisionResolverTests {
    @Test func transitiveReplacementDoesNotExpandAnIntermediateDecisionsScope() throws {
        let initial = try RecordingAssessmentTestSupport.decision(1)
        let middle = try RecordingAssessmentTestSupport.decision(
            2,
            start: 25,
            end: 50,
            action: .select(RecordingAssessmentTestSupport.second),
            predecessors: [initial.id],
        )
        let last = try RecordingAssessmentTestSupport.decision(
            3,
            start: 75,
            end: 100,
            action: .automatic,
            predecessors: [middle.id],
        )
        #expect(try resolve([last, initial, middle]).map(\.resolution) == [
            .selected(RecordingAssessmentTestSupport.first),
            .selected(RecordingAssessmentTestSupport.second),
            .selected(RecordingAssessmentTestSupport.first),
            .automatic,
        ])
    }

    private func resolve(_ decisions: [HistoryDecision]) throws
        -> [HistoryDecisionResolver.Segment]
    {
        try HistoryDecisionResolver.resolve(
            decisions,
            within: RecordingAssessmentTestSupport.period(0, 100),
            version: RecordingAssessmentTestSupport.version,
        )
    }

    @Test func preservesConcurrentChoicesUntilAnObservedReplacement() throws {
        let first = try RecordingAssessmentTestSupport.decision(1)
        let second = try RecordingAssessmentTestSupport.decision(
            2,
            action: .select(RecordingAssessmentTestSupport.second),
        )
        #expect(try resolve([first, second]).map(\.resolution) == [.conflict([
            first.id,
            second.id,
        ])])
        let replacement = try RecordingAssessmentTestSupport.decision(
            3,
            predecessors: [first.id, second.id],
        )
        #expect(try resolve([second, replacement, first])
            .map(\.resolution) == [.selected(RecordingAssessmentTestSupport.first)])
    }

    @Test func replacementsAndReversalsChangeOnlyTheirOwnPeriods() throws {
        let first = try RecordingAssessmentTestSupport.decision(1)
        let replacement = try RecordingAssessmentTestSupport.decision(
            2,
            start: 25,
            end: 75,
            action: .automatic,
            predecessors: [first.id],
        )
        let result = try resolve([replacement, first])
        #expect(result.map(\.resolution) == [
            .selected(RecordingAssessmentTestSupport.first),
            .automatic,
            .selected(RecordingAssessmentTestSupport.first),
        ])
        #expect(try result.map(\.period) == [
            RecordingAssessmentTestSupport.period(0, 25),
            RecordingAssessmentTestSupport.period(25, 75),
            RecordingAssessmentTestSupport.period(75, 100),
        ])
    }

    @Test func incompleteDependenciesDoNotSilentlySupersedeReceivedEvidence() throws {
        let first = try RecordingAssessmentTestSupport.decision(1)
        let missingID = RecordingAssessmentTestSupport.decisionID(2)
        let later = try RecordingAssessmentTestSupport.decision(
            3,
            action: .automatic,
            predecessors: [missingID],
        )
        #expect(try resolve([first, later]).map(\.resolution) == [.incomplete([missingID])])
        let middle = try RecordingAssessmentTestSupport.decision(2, predecessors: [first.id])
        #expect(try resolve([later, first, middle]).map(\.resolution) == [.automatic])
    }

    @Test func aMissingDependencyDoesNotBlockAnUnrelatedPeriod() throws {
        let first = try RecordingAssessmentTestSupport.decision(1, end: 50)
        let later = try RecordingAssessmentTestSupport.decision(
            3,
            start: 50,
            action: .automatic,
            predecessors: [RecordingAssessmentTestSupport.decisionID(2)],
        )
        #expect(try resolve([later, first]).map(\.resolution) == [
            .selected(RecordingAssessmentTestSupport.first),
            .incomplete([RecordingAssessmentTestSupport.decisionID(2)]),
        ])
    }

    @Test func concurrentAgreementRetainsBothRecordsAcrossCompatiblePolicyVersions() throws {
        let first = try RecordingAssessmentTestSupport.decision(1)
        let second = try RecordingAssessmentTestSupport.decision(
            2,
            version: .init(major: 1, minor: 9, patch: 1),
        )
        let segment = try #require(resolve([second, first]).first)
        #expect(segment.resolution == .selected(RecordingAssessmentTestSupport.first))
        #expect(segment.effectiveDecisions == [first.id, second.id])
    }

    @Test func duplicatesAndAllDeliveryOrdersConverge() throws {
        let first = try RecordingAssessmentTestSupport.decision(1)
        let second = try RecordingAssessmentTestSupport.decision(
            2,
            action: .select(RecordingAssessmentTestSupport.second),
        )
        let third = try RecordingAssessmentTestSupport.decision(
            3,
            start: 20,
            end: 80,
            action: .automatic,
            predecessors: [first.id, second.id],
        )
        let expected = try resolve([first, second, third])
        for values in [
            [first, third, second],
            [second, first, third],
            [second, third, first],
            [third, first, second],
            [third, second, first],
        ] {
            #expect(try resolve(values + values) == expected)
        }
    }

    @Test func rejectsIdentityReuseUnsupportedMajorsAndCausalCycles() throws {
        let first = try RecordingAssessmentTestSupport.decision(1)
        let reused = try RecordingAssessmentTestSupport.decision(1, action: .automatic)
        #expect(throws: HistoryDecisionResolver.ValidationError.conflictingIdentity(first.id)) {
            try resolve([
                first,
                reused,
            ])
        }
        let unsupported = try RecordingAssessmentTestSupport.decision(
            2,
            version: .init(major: 2, minor: 0, patch: 0),
        )
        #expect(throws: HistoryDecisionResolver.ValidationError.unsupportedMajor(unsupported.id)) {
            try resolve([unsupported])
        }
        let cyclic = try RecordingAssessmentTestSupport.decision(
            1,
            predecessors: [RecordingAssessmentTestSupport.decisionID(2)],
        )
        let other = try RecordingAssessmentTestSupport.decision(2, predecessors: [cyclic.id])
        #expect(throws: HistoryDecisionResolver.ValidationError.self) {
            try resolve([other, cyclic])
        }
    }
}
