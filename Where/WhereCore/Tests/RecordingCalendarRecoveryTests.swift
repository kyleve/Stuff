import Foundation
import Testing
@testable import WhereCore

struct RecordingCalendarRecoveryTests {
    @Test(arguments: RecordingCalendarRecoveryTestSupport.transitions)
    func freezesOffsetsOnEachSideOfHistoricalTransitions(
        fixture: RecordingCalendarRecoveryTestSupport.Transition,
    ) throws {
        let transition = try Date(fixture.instant, strategy: .iso8601)
        let zone = try #require(TimeZone(identifier: fixture.zoneIdentifier))
        let period = try RecordingPeriod(
            start: transition.addingTimeInterval(-3600),
            end: transition.addingTimeInterval(3600),
        )
        let recovery = try RecordingCalendarRecovery(
            deviceID: RecordingControlsTestSupport.device,
            periods: [period],
            timeZone: zone,
        )
        #expect(try recovery.segments.map(\.period) == [
            RecordingPeriod(start: period.start, end: transition),
            RecordingPeriod(start: transition, end: period.end),
        ])
        #expect(recovery.segments.map(\.context.secondsFromGMT) == [
            fixture.beforeOffset,
            fixture.afterOffset,
        ])
        #expect(recovery.segments.allSatisfy { $0.context.timeZone == zone })
        #expect(try recovery.edits.map { try $0.query().periods } == recovery.segments.map {
            [$0.period]
        })
    }

    @Test(arguments: RecordingCalendarRecoveryTestSupport.transitions)
    func aTransitionAtAnEndpointBelongsOnlyToTheFollowingPeriod(
        fixture: RecordingCalendarRecoveryTestSupport.Transition,
    ) throws {
        let transition = try Date(fixture.instant, strategy: .iso8601)
        let zone = try #require(TimeZone(identifier: fixture.zoneIdentifier))
        let before = try RecordingCalendarRecovery(
            deviceID: RecordingControlsTestSupport.device,
            periods: [.init(start: transition.addingTimeInterval(-1), end: transition)],
            timeZone: zone,
        )
        let after = try RecordingCalendarRecovery(
            deviceID: RecordingControlsTestSupport.device,
            periods: [.init(start: transition, end: transition.addingTimeInterval(1))],
            timeZone: zone,
        )
        #expect(before.segments.map(\.context.secondsFromGMT) == [fixture.beforeOffset])
        #expect(after.segments.map(\.context.secondsFromGMT) == [fixture.afterOffset])
    }

    @Test func disjointPeriodsDoNotEstablishTheUnconfirmedGap() throws {
        let periods = try [
            RecordingAssessmentTestSupport.period(0, 100),
            RecordingAssessmentTestSupport.period(200, 300),
        ]
        let recovery = try RecordingCalendarRecovery(
            deviceID: RecordingControlsTestSupport.device,
            periods: periods.reversed(),
            timeZone: .gmt,
        )
        #expect(recovery.segments.map(\.period) == periods)
        #expect(recovery.segments.allSatisfy { $0.context.secondsFromGMT == 0 })
    }

    @Test func emptyRecoveryScopeIsRejected() {
        #expect(throws: DataCompatibilityError.incompleteRecord) {
            try RecordingCalendarRecovery(
                deviceID: RecordingControlsTestSupport.device,
                periods: [],
                timeZone: .gmt,
            )
        }
    }

    @Test(arguments: RecordingCalendarRecoveryTestSupport.transitions)
    func recoversUnknownDaysWithoutChangingRawObservations(
        fixture: RecordingCalendarRecoveryTestSupport.Transition,
    ) async throws {
        let transition = try Date(fixture.instant, strategy: .iso8601)
        let zone = try #require(TimeZone(identifier: fixture.zoneIdentifier))
        let store = try await RecordingChoiceTestSupport.store()
        let samples = [-1.0, 0.0].map { offset in
            LocationSample(
                id: UUID(),
                timestamp: transition.addingTimeInterval(offset),
                coordinate: .init(latitude: 37, longitude: -122),
                horizontalAccuracy: 10,
                source: .gpsSignificantChange,
                recordingDeviceID: RecordingChoiceTestSupport.author,
                recordingDay: .unresolved,
            )
        }
        try await store.perform {
            for sample in samples {
                try await store.add(sample: sample)
            }
        }
        let recovery = try RecordingCalendarRecovery(
            deviceID: RecordingChoiceTestSupport.author,
            periods: [.init(
                start: transition.addingTimeInterval(-3600),
                end: transition.addingTimeInterval(3600),
            )],
            timeZone: zone,
        )
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let proposal = try await coordinator.review(recovery.edits)
        #expect(try await coordinator.apply(proposal) == .applied)
        let controls = try await RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).snapshot()
        let assignments = try samples.map {
            try RecordingCalendarResolver.assignment(
                for: $0,
                decisions: controls.calendarContexts.reversed(),
                version: RecordingEvidencePolicy.version,
            )
        }
        let expected = [fixture.beforeDay, fixture.afterDay]
        for (assignment, day) in zip(assignments, expected) {
            guard case let .resolved(context) = assignment else {
                Issue.record("Confirmed historical context must resolve the unknown day.")
                continue
            }
            #expect(context.day == day)
            #expect(context.timeZone == zone)
        }
        #expect(try await Set(store.allSamples()) == Set(samples))
        #expect(samples.allSatisfy { $0.recordingDay == .unresolved })
        let first = try #require(controls.calendarContexts
            .first { $0.periods.contains { $0.contains(samples[0].timestamp) } })
        #expect(try RecordingCalendarResolver.assignment(
            for: samples[1],
            decisions: [first],
            version: RecordingEvidencePolicy.version,
        ) == .unresolved)
    }
}
