import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
enum RecordingIgnoreTestSupport {
    static func ignore(
        fixture: RecordingReviewTestSupport.Fixture,
        deviceID: RecordingDeviceID,
        day: CalendarDay,
    ) async throws -> RecordingIgnoreDecision {
        let until = try RecordingIgnoreDecision.Until(day: day, timeZone: .gmt)
        let coordinator = fixture.services.recordingControlEdits
        let proposal = try await coordinator.review(.ignore(
            deviceID: deviceID,
            periods: [.init(start: RecordingReviewTestSupport.date(0), end: until.end)],
            change: .ignore(until),
        ))
        #expect(try await coordinator.apply(proposal) == .applied)
        guard case let .ignore(decision) = try #require(proposal.edits.first).control else {
            throw RecordingReviewTestSupport.TestFailure.expectedPreview
        }
        return decision
    }

    static func model(_ fixture: RecordingReviewTestSupport.Fixture) -> RecordingIgnoreModel {
        .init(
            services: fixture.services,
            deviceID: RecordingReviewTestSupport.first,
            name: "Phone One",
            now: { RecordingReviewTestSupport.date(600) },
        )
    }
}
