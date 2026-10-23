import Foundation
import Observation
import RegionKit
import WhereCore

/// Owns calendar zoom intent and restores only destinations present in the detailed calendar.
@MainActor
@Observable
final class CalendarPresentationModel {
    enum Mode: Hashable {
        case detail, overview
    }

    enum Target: Hashable {
        case month(CalendarDay)
        case estimate(CalendarDay)

        var month: CalendarDay {
            switch self {
                case let .month(month), let .estimate(month): month
            }
        }
    }

    // Ratios relative to the start of one completed pinch. Small motions do not switch modes.
    private static let overviewThreshold: CGFloat = 0.8
    private static let detailThreshold: CGFloat = 1.2

    private(set) var mode: Mode
    private(set) var target: Target?
    private(set) var year: Int?
    private(set) var availableMonths: Set<CalendarDay> = []
    private(set) var estimateMonth: CalendarDay?
    private(set) var rejectedTarget: Target?
    private(set) var rejectionCount = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func reconcile(
        year: Int,
        availableMonths: [CalendarDay],
        currentMonth: CalendarDay?,
        estimateMonth: CalendarDay?,
    ) {
        let changedYear = self.year != year
        self.year = year
        self.availableMonths = Set(availableMonths)
        self.estimateMonth = estimateMonth
        if changedYear || target.map({ !isAvailable($0) }) != false {
            target = (currentMonth.flatMap { self.availableMonths.contains($0) ? $0 : nil }
                ?? availableMonths.last).map(Target.month)
        }
        if changedYear { rejectedTarget = nil }
    }

    func isAvailable(_ target: Target) -> Bool {
        switch target {
            case let .month(month): availableMonths.contains(month)
            case let .estimate(month): estimateMonth == month
        }
    }

    func remember(_ target: Target) {
        guard mode == .detail, isAvailable(target) else { return }
        self.target = target
    }

    @discardableResult
    func expand(_ destination: Target?) -> Bool {
        guard let destination = destination ?? target else { return false }
        guard isAvailable(destination) else {
            rejectedTarget = destination
            rejectionCount += 1
            return false
        }
        target = destination
        mode = .detail
        return true
    }

    func toggle() {
        switch mode {
            case .detail: mode = .overview
            case .overview: expand(nil)
        }
    }

    func finishPinch(magnification: CGFloat, destination: Target?) {
        switch mode {
            case .detail:
                if magnification <= Self.overviewThreshold { mode = .overview }
            case .overview:
                if magnification >= Self.detailThreshold { expand(destination) }
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
