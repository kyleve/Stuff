import Foundation

/// Converts an explicitly confirmed historical zone into bounded, fixed-offset controls.
/// Every offset transition splits the interval; gaps in the requested scope stay gaps.
public struct RecordingCalendarRecovery: Hashable, Sendable {
    public struct Segment: Hashable, Sendable {
        public let period: RecordingPeriod
        public let context: RecordingCalendarContext
    }

    public enum ValidationError: Error, Equatable { case invalidTransition }

    public let deviceID: RecordingDeviceID
    public let timeZone: TimeZone
    public let segments: [Segment]

    public init(
        deviceID: RecordingDeviceID,
        periods: [RecordingPeriod],
        timeZone: TimeZone,
    ) throws {
        let query = try RecordingReviewQuery(periods: periods, deviceIDs: [deviceID])
        var segments: [Segment] = []
        for period in query.periods {
            var start = period.start
            while start < period.end {
                // Foundation returns zone-rule transitions, including non-DST changes.
                // The offset at the transition belongs to the next half-open segment.
                let transition = timeZone.nextDaylightSavingTimeTransition(after: start)
                if let transition, transition <= start {
                    throw ValidationError.invalidTransition
                }
                let end = min(transition ?? period.end, period.end)
                try segments.append(Segment(
                    period: .init(start: start, end: end),
                    context: .init(observedAt: start, timeZone: timeZone),
                ))
                start = end
            }
        }
        self.deviceID = deviceID
        self.timeZone = timeZone
        self.segments = segments
    }

    public var edits: [RecordingControlEdit] {
        segments.map { segment in
            .calendar(
                deviceID: deviceID,
                periods: [segment.period],
                action: .establish(segment.context),
            )
        }
    }
}
