import Foundation

public struct LocalTime: Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) throws {
        guard (0 ... 23).contains(hour), (0 ... 59).contains(minute) else {
            throw ThrowValidationError.outOfRange(
                field: "localTime",
                closedRange: 0 ... 1439,
            )
        }
        self.hour = hour
        self.minute = minute
    }

    public var minutesAfterMidnight: Int {
        hour * 60 + minute
    }
}

public struct DailyQuietInterval: Hashable, Sendable {
    public let start: LocalTime
    public let end: LocalTime

    public init(start: LocalTime, end: LocalTime) throws {
        guard start != end else { throw ThrowValidationError.invalidQuietInterval }
        self.start = start
        self.end = end
    }

    public var durationMinutes: Int {
        let difference = end.minutesAfterMidnight - start.minutesAfterMidnight
        return difference > 0 ? difference : difference + 24 * 60
    }

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return false }
        let value = hour * 60 + minute
        if start.minutesAfterMidnight < end.minutesAfterMidnight {
            return value >= start.minutesAfterMidnight && value < end.minutesAfterMidnight
        }
        return value >= start.minutesAfterMidnight || value < end.minutesAfterMidnight
    }

    public func nextBoundary(after date: Date, calendar: Calendar) -> Date? {
        let target = contains(date, calendar: calendar) ? end : start
        var components = DateComponents()
        components.hour = target.hour
        components.minute = target.minute
        let firstCandidate = calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward,
        )
        let lastCandidate = calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .last,
            direction: .forward,
        )
        return [firstCandidate, lastCandidate].compactMap(\.self).min()
    }
}

public struct QuietSchedule: Hashable, Sendable {
    public static let disabled = QuietSchedule(interval: nil)

    public let interval: DailyQuietInterval?

    private init(interval: DailyQuietInterval?) {
        self.interval = interval
    }

    public init(start: LocalTime, end: LocalTime) throws {
        interval = try DailyQuietInterval(start: start, end: end)
    }

    public func isQuiet(at date: Date, calendar: Calendar) -> Bool {
        interval?.contains(date, calendar: calendar) ?? false
    }

    public func nextBoundary(after date: Date, calendar: Calendar) -> Date? {
        interval?.nextBoundary(after: date, calendar: calendar)
    }
}

public enum TemporaryQuietWake: Int, CaseIterable, Hashable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case sixtyMinutes = 60

    public var duration: Duration {
        .seconds(rawValue * 60)
    }

    public var timeInterval: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}
