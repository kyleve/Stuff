import Foundation

/// Advances a fixed render deadline and drops elapsed slots instead of
/// accumulating projection work after a slow frame.
struct ProjectionFrameSchedule {
    static let interval = Duration.seconds(1.0 / 30.0)

    private(set) var nextDeadline: ContinuousClock.Instant

    init(startingAt start: ContinuousClock.Instant) {
        nextDeadline = start
    }

    mutating func advance(past now: ContinuousClock.Instant) -> ContinuousClock.Instant {
        repeat {
            nextDeadline = nextDeadline.advanced(by: Self.interval)
        } while nextDeadline <= now
        return nextDeadline
    }
}
