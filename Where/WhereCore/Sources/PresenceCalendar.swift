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

/// One cell in a month grid: a real calendar day plus the regions present that
/// day (sorted by `Region.allCases` so dot order is stable).
public struct CalendarDayCell: Hashable, Sendable, Identifiable {
    public let date: Date
    public let dayOfMonth: Int
    public let regions: [Region]
    public let isToday: Bool
    /// Whether this day still needs a location logged (matches the Primary
    /// tab's missing-day banner/backfill rules).
    public let needsAttention: Bool
    /// Whether at least one piece of evidence was captured on this day (its
    /// `capturedAt` falls on this calendar day). Drives the calendar's evidence
    /// badge. Independent of `regions`/residency — evidence is metadata only.
    public let hasEvidence: Bool

    public var id: Date {
        date
    }

    public init(
        date: Date,
        dayOfMonth: Int,
        regions: [Region],
        isToday: Bool,
        needsAttention: Bool,
        hasEvidence: Bool,
    ) {
        self.date = date
        self.dayOfMonth = dayOfMonth
        self.regions = regions
        self.isToday = isToday
        self.needsAttention = needsAttention
        self.hasEvidence = hasEvidence
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

/// A single month laid out for a grid: leading blank cells (so day 1 lands on
/// the right weekday column) followed by every day in the month.
public struct CalendarMonth: Hashable, Sendable, Identifiable {
    public let year: Int
    public let month: Int
    public let startOfMonth: Date
    public let leadingBlankCount: Int
    public let weekdayCount: Int
    public let weekdaySymbols: [String]
    public let isCurrentMonth: Bool
    public let days: [CalendarDayCell]
    /// Per-region day counts for this month, sorted by day count descending
    /// (ties broken by `Region.allCases` order). Always reflects every region
    /// present that month, regardless of any focus filter applied to `days`.
    public let regionTotals: [RegionDayTally]

    public var id: String {
        "\(year)-\(month)"
    }

    public init(
        year: Int,
        month: Int,
        startOfMonth: Date,
        leadingBlankCount: Int,
        weekdayCount: Int,
        weekdaySymbols: [String],
        isCurrentMonth: Bool,
        days: [CalendarDayCell],
        regionTotals: [RegionDayTally],
    ) {
        self.year = year
        self.month = month
        self.startOfMonth = startOfMonth
        self.leadingBlankCount = leadingBlankCount
        self.weekdayCount = weekdayCount
        self.weekdaySymbols = weekdaySymbols
        self.isCurrentMonth = isCurrentMonth
        self.days = days
        self.regionTotals = regionTotals
    }
}

/// Builds month grids from a `YearReport`. Pure calendar layout derived from
/// `DayPresence`, parallel to `PresenceTimeline` in WhereUI.
public enum PresenceCalendar {
    /// Build every month in `report.year`. `missingDates` should be start-of-day
    /// keys in the same `calendar` used here and in `DayAggregator`.
    ///
    /// When `focusedRegion` is non-nil, each day's dots are filtered to just
    /// that region (days where it wasn't present show no dots), so the calendar
    /// reads as "only the days I spent in this location". The per-month
    /// `regionTotals` footer still reflects every region present that month.
    public static func months(
        from report: YearReport,
        calendar: Calendar,
        referenceDate: Date,
        missingDates: Set<Date> = [],
        evidenceDays: Set<Date> = [],
        focusedRegion: Region? = nil,
    ) throws -> [CalendarMonth] {
        var regionsByDay: [Date: Set<Region>] = [:]
        for day in report.days {
            let key = calendar.startOfDay(for: day.date)
            regionsByDay[key] = day.regions
        }

        guard
            let yearStart = calendar.date(from: DateComponents(
                year: report.year,
                month: 1,
                day: 1,
            ))
        else {
            throw PresenceCalendarError.missingYearStart(year: report.year)
        }
        guard let monthRange = calendar.range(of: .month, in: .year, for: yearStart) else {
            throw PresenceCalendarError.missingMonthRange(year: report.year)
        }

        let normalizedMissing = Set(missingDates.map { calendar.startOfDay(for: $0) })
        let normalizedEvidence = Set(evidenceDays.map { calendar.startOfDay(for: $0) })
        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)

        return try monthRange.map { monthNumber in
            try Self.month(
                year: report.year,
                month: monthNumber,
                regionsByDay: regionsByDay,
                calendar: calendar,
                referenceDate: referenceStartOfDay,
                missingDates: normalizedMissing,
                evidenceDays: normalizedEvidence,
                focusedRegion: focusedRegion,
            )
        }
    }

    public static func month(
        year: Int,
        month: Int,
        regionsByDay: [Date: Set<Region>],
        calendar: Calendar,
        referenceDate: Date,
        missingDates: Set<Date> = [],
        evidenceDays: Set<Date> = [],
        focusedRegion: Region? = nil,
    ) throws -> CalendarMonth {
        guard
            let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        else {
            throw PresenceCalendarError.missingMonthStart(year: year, month: month)
        }
        let startOfMonth = calendar.startOfDay(for: firstOfMonth)
        guard let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            throw PresenceCalendarError.missingDayRange(year: year, month: month)
        }
        let numberOfDays = dayRange.count
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let weekdayCount = try Self.weekdayCount(in: calendar)
        let leadingBlankCount = (weekday - calendar.firstWeekday + weekdayCount) % weekdayCount
        let weekdaySymbols = Self.orderedWeekdaySymbols(in: calendar)
        let isCurrentMonth = calendar.isDate(
            startOfMonth,
            equalTo: referenceDate,
            toGranularity: .month,
        )

        var days: [CalendarDayCell] = []
        days.reserveCapacity(numberOfDays)
        var dayCountsByRegion: [Region: Int] = [:]
        for dayOfMonth in 1 ... numberOfDays {
            guard
                let date = calendar.date(
                    byAdding: .day,
                    value: dayOfMonth - 1,
                    to: startOfMonth,
                )
            else {
                throw PresenceCalendarError.missingDayDate(
                    year: year,
                    month: month,
                    day: dayOfMonth,
                )
            }
            let presentRegions = regionsByDay[date] ?? []
            for region in presentRegions {
                dayCountsByRegion[region, default: 0] += 1
            }
            // Dots reflect the focus filter; the footer (regionTotals) keeps
            // counting every region present that day.
            let regions = Region.allCases.filter { region in
                presentRegions.contains(region) && (focusedRegion == nil || region == focusedRegion)
            }
            days.append(CalendarDayCell(
                date: date,
                dayOfMonth: dayOfMonth,
                regions: regions,
                isToday: calendar.isDate(date, inSameDayAs: referenceDate),
                needsAttention: missingDates.contains(date),
                hasEvidence: evidenceDays.contains(date),
            ))
        }

        let regionTotals = Region.rankedByDayCount(
            dayCountsByRegion.map { RegionDayTally(region: $0.key, days: $0.value) },
            days: \.days,
            region: \.region,
        )

        return CalendarMonth(
            year: year,
            month: month,
            startOfMonth: startOfMonth,
            leadingBlankCount: leadingBlankCount,
            weekdayCount: weekdayCount,
            weekdaySymbols: weekdaySymbols,
            isCurrentMonth: isCurrentMonth,
            days: days,
            regionTotals: regionTotals,
        )
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
    /// Month grids for the calendar sheet. Pass the same `calendar` and
    /// start-of-day `missingDates` keys used by `MissingDays` and
    /// `DayAggregator`.
    public func calendarMonths(
        calendar: Calendar,
        referenceDate: Date,
        missingDates: Set<Date> = [],
        evidenceDays: Set<Date> = [],
        focusedRegion: Region? = nil,
    ) throws -> [CalendarMonth] {
        try PresenceCalendar.months(
            from: self,
            calendar: calendar,
            referenceDate: referenceDate,
            missingDates: missingDates,
            evidenceDays: evidenceDays,
            focusedRegion: focusedRegion,
        )
    }
}
