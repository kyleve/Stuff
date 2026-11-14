import Foundation
import RegionKit
import WhereCore

/// Interprets calendar data and reads/writes the existing per-calendar zoom preference.
@MainActor
struct CalendarModel {
    let report: YearReportModel
    let persistenceKey: CalendarZoomKey?

    func isOverview(fallback: Bool) -> Bool {
        persistenceKey.flatMap { report.preferences.calendarOverview(forKey: $0) } ?? fallback
    }

    func setOverview(_ value: Bool) {
        guard let persistenceKey else { return }
        report.preferences.setCalendarOverview(value, forKey: persistenceKey)
    }

    /// Inputs that invalidate a cached month grid.
    struct LoadID: Equatable {
        let report: YearReport
        let missingDayKeys: Set<CalendarDay>
        let evidenceDayKeys: Set<CalendarDay>
        let flightDayKeys: Set<CalendarDay>
        let referenceDay: Date
        let focusedRegion: Region?
    }

    func loadID(for yearReport: YearReport, focusedRegion: Region?) -> LoadID {
        LoadID(
            report: yearReport,
            missingDayKeys: report.missingDayKeys,
            evidenceDayKeys: report.evidenceDayKeys,
            flightDayKeys: report.flightDayKeys,
            referenceDay: report.calendar.startOfDay(for: report.referenceDate),
            focusedRegion: focusedRegion,
        )
    }

    func months(
        from yearReport: YearReport,
        focusedRegion: Region?,
    ) -> Result<[CalendarMonth], Error> {
        Result {
            try yearReport.calendarMonths(
                calendar: report.calendar,
                referenceDate: report.referenceDate,
                missingDates: report.missingDayKeys,
                evidenceDays: report.evidenceDayKeys,
                flightDays: report.flightDayKeys,
                focusedRegion: focusedRegion,
            )
        }
    }

    /// The months to show in chronological order. Future months are omitted
    /// unless a planned stay reaches into them; a past year shows the full year.
    static func visibleMonths(
        _ months: [CalendarMonth],
        report: YearReportModel,
        focusedRegion: Region?,
    ) -> [CalendarMonth] {
        guard
            let currentMonthStart = report.calendar
            .dateInterval(of: .month, for: report.referenceDate)?
            .start
        else {
            return months
        }
        let lastPlannedDay = report.showsEstimatedTimeAndPlanning
            ? report.forecasts.plannedIntervals(intersecting: report.selectedYear)
            .filter { focusedRegion == nil || $0.region == focusedRegion }
            .map(\.end).max()
            : nil
        let showsHome = report.showsEstimatedTimeAndPlanning
            && report.forecasts.planning.homeRegion != nil
            && (focusedRegion == nil || report.forecasts.planning.homeRegion == focusedRegion)
        let finalDay = showsHome ? CalendarDay.lastDay(ofYear: report.selectedYear) : lastPlannedDay
        if finalDay == nil,
           report.selectedYear > report.calendar.component(.year, from: report.referenceDate)
        {
            // The year selector retains this selection after plans are hidden or deleted.
            return months
        }
        let lastShownMonth = finalDay.map {
            CalendarDay(year: $0.year, month: $0.month, day: 1).startOfDay(in: report.calendar)
        }.map { max(currentMonthStart, $0) } ?? currentMonthStart
        return months.filter { $0.startOfMonth <= lastShownMonth }
    }
}
