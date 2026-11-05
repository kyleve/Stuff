import Foundation
import RegionKit

public enum PresenceCalendarError: Error, Equatable {
    case missingWeekdayRange
    case missingYearStart(year: Int)
    case missingMonthRange(year: Int)
    case missingMonthStart(year: Int, month: Int)
    case missingDayRange(year: Int, month: Int)
    case missingDayDate(year: Int, month: Int, day: Int)
}

/// One cell in a month grid: a logical calendar day plus the regions present that
/// day (sorted by `Region.allCases` so dot order is stable).
public struct CalendarDayCell: Hashable, Sendable, Identifiable {
    public let day: CalendarDay
    public var dayOfMonth: Int {
        day.day
    }

    public let regions: [Region]
    public let isToday: Bool
    /// Whether this day still needs a location logged (matches the Primary
    /// tab's missing-day banner/backfill rules).
    public let needsAttention: Bool
    /// Whether at least one piece of evidence was captured on this day (its
    /// `capturedAt` falls on this calendar day). Drives the calendar's evidence
    /// badge. Independent of `regions`/residency — evidence is metadata only.
    public let hasEvidence: Bool
    public let hasFlight: Bool

    public var id: CalendarDay {
        day
    }

    public init(
        day: CalendarDay,
        regions: [Region],
        isToday: Bool,
        needsAttention: Bool,
        hasEvidence: Bool,
        hasFlight: Bool,
    ) {
        self.day = day
        self.regions = regions
        self.isToday = isToday
        self.needsAttention = needsAttention
        self.hasEvidence = hasEvidence
        self.hasFlight = hasFlight
    }
}

/// How many distinct days a region was present in a single month — the data
/// behind the month grid's footer. Computed from the full (unfiltered) day
/// presence, so it lists every location that month even when the calendar is
/// focused on one region.
public struct RegionDayTally: Hashable, Sendable, Identifiable {
    public let region: Region
    public let days: Int

    public var id: Region {
        region
    }

    public init(region: Region, days: Int) {
        self.region = region
        self.days = days
    }
}

/// How many distinct days shared one exact multi-region combination in a
/// single month. Regions are stored in canonical catalog order; single-region
/// days stay in ``RegionDayTally`` and never appear here.
public struct RegionCombinationDayTally: Hashable, Sendable, Identifiable {
    public let regions: [Region]
    public let days: Int

    public var id: [Region] {
        regions
    }

    public init(regions: Set<Region>, days: Int) {
        precondition(regions.count > 1, "A region combination requires at least two regions.")
        precondition(days > 0, "A region combination day count must be positive.")
        self.regions = Region.inCanonicalOrder(regions)
        self.days = days
    }
}

/// A single month laid out for a grid: leading blank cells (so day 1 lands on
/// the right weekday column) followed by every day in the month.
public struct CalendarMonth: Hashable, Sendable, Identifiable {
    public let year: Int
    public let month: Int
    public var firstDay: CalendarDay {
        CalendarDay(year: year, month: month, day: 1)
    }

    public let leadingBlankCount: Int
    public let weekdayCount: Int
    public let weekdaySymbols: [String]
    public let isCurrentMonth: Bool
    public let days: [CalendarDayCell]
    /// Per-region day counts for this month, sorted by day count descending
    /// (ties broken by `Region.allCases` order). Always reflects every region
    /// present that month, regardless of any focus filter applied to `days`.
    public let regionTotals: [RegionDayTally]
    /// Exact multi-region combinations for the month, counted from full day
    /// presence before any focused-calendar filtering is applied.
    public let regionCombinationTotals: [RegionCombinationDayTally]

    public var id: CalendarDay {
        firstDay
    }

    public init(
        year: Int,
        month: Int,
        leadingBlankCount: Int,
        weekdayCount: Int,
        weekdaySymbols: [String],
        isCurrentMonth: Bool,
        days: [CalendarDayCell],
        regionTotals: [RegionDayTally],
        regionCombinationTotals: [RegionCombinationDayTally],
    ) {
        self.year = year
        self.month = month
        self.leadingBlankCount = leadingBlankCount
        self.weekdayCount = weekdayCount
        self.weekdaySymbols = weekdaySymbols
        self.isCurrentMonth = isCurrentMonth
        self.days = days
        self.regionTotals = regionTotals
        self.regionCombinationTotals = regionCombinationTotals
    }
}

/// Builds month grids from a `YearReport`. Pure calendar layout derived from
/// `DayPresence`, parallel to `PresenceTimeline` in WhereUI.
public enum PresenceCalendar {
    private static let logger = WhereLog.reporting(PresenceCalendarLog.self)

    /// Build every month in `report.year`. `missingDates` and `evidenceDays` are
    /// `CalendarDay`s. Layout preserves Gregorian dates even when the viewing zone skipped one.
    /// `calendar` supplies the locale, week start, and zone used to identify today's logical date.
    ///
    /// When `focusedRegion` is non-nil, each day's dots are filtered to just
    /// that region (days where it wasn't present show no dots), so the calendar
    /// reads as "only the days I spent in this location". The per-month
    /// `regionTotals` footer still reflects every region present that month.
    public static func months(
        from report: YearReport,
        calendar: Calendar,
        referenceDate: Date,
        missingDates: Set<CalendarDay> = [],
        evidenceDays: Set<CalendarDay> = [],
        flightDays: Set<CalendarDay>,
        focusedRegion: Region? = nil,
    ) throws -> [CalendarMonth] {
        try logger.measure(.layoutYear, budget: .milliseconds(500)) {
            let layoutCalendar = logicalCalendar(from: calendar)
            var regionsByDay: [CalendarDay: Set<Region>] = [:]
            for day in report.days {
                regionsByDay[day.day] = day.regions
            }

            guard
                let yearStart = layoutCalendar.date(from: DateComponents(
                    year: report.year,
                    month: 1,
                    day: 1,
                ))
            else {
                throw PresenceCalendarError.missingYearStart(year: report.year)
            }
            guard let monthRange = layoutCalendar.range(of: .month, in: .year, for: yearStart)
            else {
                throw PresenceCalendarError.missingMonthRange(year: report.year)
            }

            return try monthRange.map { monthNumber in
                try Self.month(
                    year: report.year,
                    month: monthNumber,
                    regionsByDay: regionsByDay,
                    calendar: calendar,
                    referenceDate: referenceDate,
                    missingDates: missingDates,
                    evidenceDays: evidenceDays,
                    flightDays: flightDays,
                    focusedRegion: focusedRegion,
                )
            }
        }
    }

    public static func month(
        year: Int,
        month: Int,
        regionsByDay: [CalendarDay: Set<Region>],
        calendar: Calendar,
        referenceDate: Date,
        missingDates: Set<CalendarDay> = [],
        evidenceDays: Set<CalendarDay> = [],
        flightDays: Set<CalendarDay>,
        focusedRegion: Region? = nil,
    ) throws -> CalendarMonth {
        let layoutCalendar = logicalCalendar(from: calendar)
        var referenceCalendar = layoutCalendar
        referenceCalendar.timeZone = calendar.timeZone
        let referenceDay = CalendarDay(from: referenceDate, in: referenceCalendar)
        guard
            let firstOfMonth = layoutCalendar.date(from: DateComponents(
                year: year,
                month: month,
                day: 1,
            ))
        else {
            throw PresenceCalendarError.missingMonthStart(year: year, month: month)
        }
        guard let dayRange = layoutCalendar.range(of: .day, in: .month, for: firstOfMonth) else {
            throw PresenceCalendarError.missingDayRange(year: year, month: month)
        }
        let numberOfDays = dayRange.count
        let weekday = layoutCalendar.component(.weekday, from: firstOfMonth)
        let weekdayCount = try Self.weekdayCount(in: layoutCalendar)
        let leadingBlankCount = (weekday - layoutCalendar.firstWeekday + weekdayCount) %
            weekdayCount
        let weekdaySymbols = Self.orderedWeekdaySymbols(in: layoutCalendar)
        let isCurrentMonth = referenceDay.year == year && referenceDay.month == month

        var days: [CalendarDayCell] = []
        days.reserveCapacity(numberOfDays)
        var dayCountsByRegion: [Region: Int] = [:]
        var dayCountsByRegionCombination: [Set<Region>: Int] = [:]
        for dayOfMonth in 1 ... numberOfDays {
            let calendarDay = CalendarDay(year: year, month: month, day: dayOfMonth)
            let presentRegions = regionsByDay[calendarDay] ?? []
            for region in presentRegions {
                dayCountsByRegion[region, default: 0] += 1
            }
            if presentRegions.count > 1 {
                dayCountsByRegionCombination[presentRegions, default: 0] += 1
            }
            // Dots reflect the focus filter; the footer (regionTotals) keeps
            // counting every region present that day.
            let regions = Region.inCanonicalOrder(
                presentRegions.filter { focusedRegion == nil || $0 == focusedRegion },
            )
            days.append(CalendarDayCell(
                day: calendarDay,
                regions: regions,
                isToday: calendarDay == referenceDay,
                needsAttention: missingDates.contains(calendarDay),
                hasEvidence: evidenceDays.contains(calendarDay),
                hasFlight: flightDays.contains(calendarDay),
            ))
        }

        let regionTotals = Region.rankedByDayCount(
            dayCountsByRegion.map { RegionDayTally(region: $0.key, days: $0.value) },
            days: \.days,
            region: \.region,
        )
        let regionCombinationTotals = dayCountsByRegionCombination
            .map { RegionCombinationDayTally(regions: $0.key, days: $0.value) }
            .sorted { lhs, rhs in
                if lhs.days != rhs.days {
                    return lhs.days > rhs.days
                }
                return lhs.regions.lexicographicallyPrecedes(rhs.regions) { lhs, rhs in
                    Region.declarationOrder[lhs, default: 0]
                        < Region.declarationOrder[rhs, default: 0]
                }
            }

        return CalendarMonth(
            year: year,
            month: month,
            leadingBlankCount: leadingBlankCount,
            weekdayCount: weekdayCount,
            weekdaySymbols: weekdaySymbols,
            isCurrentMonth: isCurrentMonth,
            days: days,
            regionTotals: regionTotals,
            regionCombinationTotals: regionCombinationTotals,
        )
    }

    private static func logicalCalendar(from calendar: Calendar) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = .gmt
        result.locale = calendar.locale
        result.firstWeekday = calendar.firstWeekday
        return result
    }

    private static func weekdayCount(in calendar: Calendar) throws -> Int {
        guard let count = calendar.maximumRange(of: .weekday)?.count else {
            throw PresenceCalendarError.missingWeekdayRange
        }
        return count
    }

    private static func orderedWeekdaySymbols(in calendar: Calendar) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}

extension YearReport {
    /// Month grids for the calendar sheet. Pass the same `calendar` used by
    /// `DayAggregator`; `missingDates`/`evidenceDays` are `CalendarDay`s.
    public func calendarMonths(
        calendar: Calendar,
        referenceDate: Date,
        missingDates: Set<CalendarDay> = [],
        evidenceDays: Set<CalendarDay> = [],
        flightDays: Set<CalendarDay>,
        focusedRegion: Region? = nil,
    ) throws -> [CalendarMonth] {
        try PresenceCalendar.months(
            from: self,
            calendar: calendar,
            referenceDate: referenceDate,
            missingDates: missingDates,
            evidenceDays: evidenceDays,
            flightDays: flightDays,
            focusedRegion: focusedRegion,
        )
    }
}
