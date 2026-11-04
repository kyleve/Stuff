import Foundation

/// An observation's device-local Gregorian day, or explicit lack of observation-time context.
/// Capture and conversion supply the historical zone. This type never substitutes the current zone.
public enum RecordingDayAssignment: Hashable, Sendable {
    public struct Context: Hashable, Sendable {
        public enum ValidationError: Error {
            case invalidTimestamp
        }

        public let day: CalendarDay
        public let timeZone: TimeZone
        public let secondsFromGMT: Int

        public init(observedAt timestamp: Date, timeZone: TimeZone) throws {
            guard timestamp.timeIntervalSinceReferenceDate.isFinite else {
                throw ValidationError.invalidTimestamp
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let components = calendar.dateComponents([.era, .year, .month, .day], from: timestamp)
            guard components.era == 1,
                  let year = components.year, (1 ... 9999).contains(year),
                  let month = components.month, let day = components.day
            else { throw ValidationError.invalidTimestamp }
            self.day = CalendarDay(year: year, month: month, day: day)
            self.timeZone = timeZone
            secondsFromGMT = timeZone.secondsFromGMT(for: timestamp)
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
