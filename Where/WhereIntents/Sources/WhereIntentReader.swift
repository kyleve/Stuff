import Foundation
import RegionKit
import WhereCore

/// Answers query intents from one assessed report, with eligibility narrowed to the requested
/// dates.
/// Widgets are published independently and cannot establish current history or completeness here.
struct WhereIntentReader {
    let services: WhereServices
    var calendar = Calendar.whereIntents
    var now: @Sendable () -> Date = { Date() }

    /// A year count is answerable only when every potentially contributing date is resolved.
    func dayCount(in region: Region, year: Int) async throws -> Int {
        let report = try await services.reports.yearReport(for: year)
        try services.validateDataAccess()
        try requireComplete(report.completeness)
        return report.totals[region] ?? 0
    }

    /// Unresolved history outside this logical date cannot suppress an otherwise complete answer.
    func regions(on date: Date) async throws -> Set<Region> {
        let day = CalendarDay(from: date, in: calendar)
        let report = try await services.reports.yearReport(for: day.year)
        try services.validateDataAccess()
        try requireComplete(report.completeness.restricted(to: day ... day))
        return report.days.first { $0.day == day }?.regions ?? []
    }

    func todayRegions() async throws -> Set<Region> {
        try await regions(on: now())
    }

    private func requireComplete(_ completeness: HistoryCompleteness) throws {
        do {
            try completeness.requireComplete()
        } catch let error as UnresolvedHistoryError {
            throw IntentHistoryReviewError(underlyingError: error)
        }
    }
}

/// A spoken recovery action that retains Core's unresolved scope for diagnostics and callers.
struct IntentHistoryReviewError: LocalizedError {
    let underlyingError: UnresolvedHistoryError

    var errorDescription: String? {
        IntentStrings.historyNeedsReview
    }
}
