import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct RecordingChoicePresentationTests {
    @Test func routeIdentityKeepsDevicesAndDisjointReviewedPeriodsSeparate() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let periods = try [
            RecordingPeriod(
                start: RecordingReviewTestSupport.date(0),
                end: RecordingReviewTestSupport.date(601),
            ),
            RecordingPeriod(
                start: RecordingReviewTestSupport.date(1200),
                end: RecordingReviewTestSupport.date(1201),
            ),
        ]
        let model = RecordingChoiceModel(services: fixture.services, periods: periods)
        await model.review(.init(
            scope: .periods(periods),
            action: .select(RecordingReviewTestSupport.first),
        ))
        let presentation = try #require(model.presentation)
        guard case let .comparison(comparison) = presentation.result else {
            Issue.record("A period proposal must have a prepared comparison")
            return
        }
        #expect(presentation.periods == periods)
        #expect(comparison.tracks.count == 2)
        let routes = comparison.tracks.flatMap(\.map.routes)
        #expect(routes.count == 4)
        #expect(Set(routes.map(\.id)).count == 4)
        for track in comparison.tracks {
            #expect(track.observations.count == 3)
            #expect(track.map.routes.map(\.coordinates.count) == [2, 1])
            #expect(track.map.routes.map(\.id) == periods.map { .coverage(
                deviceID: track.id,
                period: $0,
            ) })
            #expect(track.days == .known([RecordingReviewTestSupport.day]))
        }
        #expect(try await fixture.controls().sourceChoices.isEmpty)
    }

    @Test func unavailableCoverageNeverConnectsAcrossARecordingGap() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let late = try RecordingReviewTestSupport.sample(
            deviceID: RecordingReviewTestSupport.first,
            seconds: 6000,
        )
        try await fixture.add([late])
        let periods = try [RecordingPeriod(
            start: RecordingReviewTestSupport.date(0),
            end: RecordingReviewTestSupport.date(6001),
        )]
        let model = RecordingChoiceModel(services: fixture.services, periods: periods)
        await model.load()
        let presentation = try #require(model.presentation)
        guard case let .comparison(comparison) = presentation.result else {
            Issue.record("Expected inspection")
            return
        }
        let track = try #require(comparison.tracks
            .first { $0.id == RecordingReviewTestSupport.first })
        #expect(track.map.routes.count == 2)
        #expect(track.map.routes.last?.coordinates == [late.coordinate])
        #expect(track.observations.count == 4)
        #expect(track.gaps.contains { $0.contains(RecordingReviewTestSupport.date(3000)) })
        #expect(!model.canApply)
    }

    @Test func unknownRecordingDaysStayUnknownAndDoNotAcquireContributions() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: true)
        let model = RecordingChoiceModel(services: fixture.services, periods: fixture.periods)
        await model.review(.init(
            scope: .periods(fixture.periods),
            action: .select(RecordingReviewTestSupport.first),
        ))
        let presentation = try #require(model.presentation)
        guard case let .comparison(comparison) = presentation.result else {
            Issue.record("A fixed-period review must remain available")
            return
        }
        #expect(comparison.tracks.allSatisfy { $0.days == .unassigned(known: []) })
        #expect(comparison.before.isEmpty)
        #expect(comparison.after.isEmpty)
        #expect(comparison.remainingIssues.isEmpty == false)
        await model.review(.init(
            scope: .recordingDay(
                deviceID: RecordingReviewTestSupport.first,
                day: RecordingReviewTestSupport.day,
            ),
            action: .select(RecordingReviewTestSupport.first),
        ))
        let wholeDay = try #require(model.presentation)
        guard case let .needsCalendarContext(missing) = wholeDay.result else {
            Issue.record("A whole-day request must retain its clarification")
            return
        }
        #expect(!missing.isEmpty)
        #expect(wholeDay.periods.isEmpty)
        #expect(!model.canApply)
    }
}
