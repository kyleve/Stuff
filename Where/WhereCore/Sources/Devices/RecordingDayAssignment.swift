import Foundation

/// An observation's device-local Gregorian day, or explicit lack of observation-time context.
/// Capture and conversion supply the historical zone. This type never substitutes the current zone.
public enum RecordingDayAssignment: Hashable, Codable, Sendable {
    public struct Context: Hashable, Codable, Sendable {
        public enum ValidationError: Error {
            case invalidTimestamp
            case invalidContext
        }

        public let day: CalendarDay
        public let timeZone: TimeZone
        public let secondsFromGMT: Int

        public init(observedAt timestamp: Date, timeZone: TimeZone) throws {
            guard timestamp.timeIntervalSinceReferenceDate.isFinite
            else { throw ValidationError.invalidTimestamp }
            try self.init(
                observedAt: timestamp,
                calendarContext: RecordingCalendarContext(
                    observedAt: timestamp,
                    timeZone: timeZone,
                ),
            )
        }

        public init(observedAt timestamp: Date, calendarContext: RecordingCalendarContext) throws {
            guard timestamp.timeIntervalSinceReferenceDate.isFinite else {
                throw ValidationError.invalidTimestamp
            }
            let calendar = try calendarContext.calendar()
            let components = calendar.dateComponents([.era, .year, .month, .day], from: timestamp)
            guard components.era == 1,
                  let year = components.year, (1 ... 9999).contains(year),
                  let month = components.month, let day = components.day
            else { throw ValidationError.invalidTimestamp }
            self.day = CalendarDay(year: year, month: month, day: day)
            timeZone = calendarContext.timeZone
            secondsFromGMT = calendarContext.secondsFromGMT
        }

        public func validate() throws {
            guard (1 ... 9999).contains(day.year), CalendarDay(iso: day.iso8601) == day,
                  TimeZone(secondsFromGMT: secondsFromGMT) != nil
            else {
                throw ValidationError.invalidContext
            }
        }

        /// Validate against the offset captured with the observation. A later time-zone database
        /// revision must not reinterpret a persisted logical day or reject its original offset.
        func matches(observedAt timestamp: Date) -> Bool {
            guard timestamp.timeIntervalSinceReferenceDate.isFinite,
                  CalendarDay(iso: day.iso8601) == day,
                  let capturedZone = TimeZone(secondsFromGMT: secondsFromGMT) else { return false }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = capturedZone
            let components = calendar.dateComponents([.era, .year, .month, .day], from: timestamp)
            return components.era == 1 && components.year == day.year
                && (1 ... 9999).contains(day.year)
                && components.month == day.month && components.day == day.day
        }
    }

    case resolved(Context)
    case unresolved

    public var day: CalendarDay? {
        switch self {
            case let .resolved(context): context.day
            case .unresolved: nil
        }
    }
}
