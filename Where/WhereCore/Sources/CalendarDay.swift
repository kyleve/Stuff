import Foundation

/// A timezone-independent calendar day (year / month / day) — the stable
/// identity of a logical day in the Where domain.
///
/// A `Date` is an absolute instant, and *which* calendar day it names depends on
/// the time zone you read it in: midnight April 1 in New York is 9pm March 31 in
/// San Francisco. Persisting a user-asserted day (a manual override or backfill)
/// or a dismissal key as an instant therefore makes it silently drift onto a
/// different day when the device changes time zones — the bug this type exists
/// to prevent. `CalendarDay` pins the day to its `year`/`month`/`day` so it means
/// the same thing everywhere; resolve a concrete `Date` only when you actually
/// need an instant (calendar-grid geometry, store range queries) via
/// `startOfDay(in:)`.
///
/// Day arithmetic (`adding(days:)`, `days(through:)`, adjacency) is pure
/// Gregorian and does not depend on any caller's time zone, so two `CalendarDay`s
/// compare and step identically regardless of where the device is.
public struct CalendarDay: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The calendar day `date` falls on when read in `calendar` (whose time zone
    /// decides the day boundaries).
    public init(from date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Recover the calendar day a *legacy* start-of-day instant was meant to
    /// represent, robust to the time zone it was written in. Legacy day keys were
    /// midnight in the writer's zone; reading such an instant directly in a zone
    /// west of the writer lands on the previous day, so we nudge ~12h toward local
    /// noon before reading the components in `calendar`. Correct for every
    /// realistic zone offset (best-effort only at the ±12h extremes). Used only by
    /// the `CalendarDay` data migration.
    public init(recoveringLegacyStartOfDay instant: Date, in calendar: Calendar) {
        self.init(from: instant.addingTimeInterval(12 * 60 * 60), in: calendar)
    }

    /// Parse the `YYYY-MM-DD` form produced by `description`. Returns `nil` for
    /// anything that isn't three correctly-padded fields *and* a real Gregorian
    /// date, so a corrupt persisted key (`2026-13-01`, `2026-02-31`) can't decode
    /// as a bogus day.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1 ... 12).contains(month), (1 ... 31).contains(day)
        else { return nil }
        // Reject impossible dates: the components must survive a round-trip
        // through the Gregorian calendar unchanged (Feb 31 would roll to March).
        let components = DateComponents(year: year, month: month, day: day)
        let calendar = Self.arithmeticCalendar
        guard let resolved = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: resolved)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The first instant of this day in `calendar` — the start-of-day `Date` for
    /// grid layout and store range queries. Falls back to the epoch only for a
    /// calendar that can't resolve the components (an impossible state we assert
    /// on in debug rather than paper over).
    public func startOfDay(in calendar: Calendar) -> Date {
        guard let date = calendar.date(
            from: DateComponents(year: year, month: month, day: day),
        ) else {
            assertionFailure("Calendar could not resolve \(self)")
            return Date(timeIntervalSince1970: 0)
        }
        return calendar.startOfDay(for: date)
    }

    /// This day shifted by `count` days (negative to go backward), computed with
    /// pure Gregorian arithmetic independent of any time zone.
    public func adding(days count: Int) -> CalendarDay {
        let calendar = Self.arithmeticCalendar
        let start = calendar.date(
            from: DateComponents(year: year, month: month, day: day),
        ) ?? Date(timeIntervalSince1970: 0)
        let shifted = calendar.date(byAdding: .day, value: count, to: start) ?? start
        return CalendarDay(from: shifted, in: calendar)
    }

    /// Every day in the inclusive range `self ... end`. Empty when `end` is
    /// before `self`.
    public func days(through end: CalendarDay) -> [CalendarDay] {
        guard self <= end else { return [] }
        var result: [CalendarDay] = []
        var cursor = self
        while cursor <= end {
            result.append(cursor)
            cursor = cursor.adding(days: 1)
        }
        return result
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let iso = try container.decode(String.self)
        guard let value = CalendarDay(iso: iso) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid CalendarDay: \(iso)",
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// A fixed UTC Gregorian calendar for day arithmetic. `CalendarDay` is
    /// timezone-independent, so stepping to the next day must not depend on the
    /// caller's zone — only on Gregorian month/year lengths.
    private static let arithmeticCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}
