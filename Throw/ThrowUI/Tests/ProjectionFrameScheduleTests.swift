import Testing
@testable import ThrowUI

struct ProjectionFrameScheduleTests {
    @Test func advancesToTheNextFixedDeadline() {
        let clock = ContinuousClock()
        let start = clock.now
        var schedule = ProjectionFrameSchedule(startingAt: start)

        let next = schedule.advance(past: start)

        #expect(next == start.advanced(by: ProjectionFrameSchedule.interval))
    }

    @Test func skipsEveryDeadlineThatElapsedDuringSlowWork() {
        let clock = ContinuousClock()
        let start = clock.now
        var schedule = ProjectionFrameSchedule(startingAt: start)
        let late = start.advanced(by: .seconds(0.1))

        let next = schedule.advance(past: late)

        #expect(next > late)
        #expect(next <= late.advanced(by: ProjectionFrameSchedule.interval))
    }
}
