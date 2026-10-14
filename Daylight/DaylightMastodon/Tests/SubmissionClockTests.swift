import DaylightCore
@testable import DaylightMastodon
import Foundation
import Testing

struct SubmissionClockTests {
    @Test(arguments: [0.0, 60, 3499])
    func acceptsElapsedTimeWithinSameBoot(seconds: TimeInterval) throws {
        let start = Date(timeIntervalSince1970: 10000)
        try SubmissionClock(date: start, uptime: 100).validate(
            date: start.addingTimeInterval(seconds),
            uptime: 100 + seconds,
        )
    }

    @Test(arguments: [3500.0, 3601, -1])
    func rejectsExpiryAndReversedTime(seconds: TimeInterval) {
        let start = Date(timeIntervalSince1970: 10000)
        #expect(throws: PublishingFailure.self) {
            try SubmissionClock(date: start, uptime: 100).validate(
                date: start.addingTimeInterval(seconds),
                uptime: 100 + seconds,
            )
        }
    }

    @Test func rejectsClockAdjustmentAndReboot() {
        let start = Date(timeIntervalSince1970: 10000)
        let clock = SubmissionClock(date: start, uptime: 100)
        #expect(throws: PublishingFailure.self) { try clock.validate(
            date: start.addingTimeInterval(30),
            uptime: 160,
        ) }
        #expect(throws: PublishingFailure.self) { try clock.validate(
            date: start.addingTimeInterval(30),
            uptime: 10,
        ) }
    }
}
