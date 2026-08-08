import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

struct FeatureDiscoveryPresentationTests {
    @Test func sparseReportUsesFallbackContent() throws {
        let calendar = calendar()
        let referenceDate = try referenceDate(in: calendar)
        let report = report(
            year: 2026,
            starting: CalendarDay(year: 2026, month: 1, day: 1),
            dayCount: FeatureDiscoveryPresentation.minimumLoggedDayCount - 1,
        )

        let presentation = FeatureDiscoveryPresentation(
            report: report,
            selectedYear: report.year,
            referenceDate: referenceDate,
            calendar: calendar,
        )

        #expect(presentation.usesUserData == false)
        #expect(presentation.widgetSnapshot.totals.isEmpty)
        #expect(presentation.widgetSnapshot.dayRegions.isEmpty)
        #expect(presentation.siriExample(for: .daysInRegion) == nil)
    }

    @Test func twoWeeksPersonalizesContent() throws {
        let calendar = calendar()
        let referenceDate = try referenceDate(in: calendar)
        let report = report(
            year: 2026,
            starting: CalendarDay(year: 2026, month: 7, day: 26),
            dayCount: FeatureDiscoveryPresentation.minimumLoggedDayCount,
        )

        let presentation = FeatureDiscoveryPresentation(
            report: report,
            selectedYear: report.year,
            referenceDate: referenceDate,
            calendar: calendar,
        )
        let daysExample = try #require(presentation.siriExample(for: .daysInRegion))
        let todayExample = try #require(presentation.siriExample(for: .todayRegions))

        #expect(presentation.usesUserData)
        #expect(presentation.widgetSnapshot.year == 2026)
        #expect(presentation.widgetSnapshot.dayRegions == Set([Region.california]))
        #expect(presentation.widgetSnapshot.totals == [Region.california: 14])
        #expect(daysExample.response.contains(Region.california.localizedName))
        #expect(daysExample.response.contains("14"))
        #expect(todayExample.response.contains(Region.california.localizedName))
    }

    @Test func futureDaysDoNotUnlockPersonalization() throws {
        let calendar = calendar()
        let referenceDate = try referenceDate(in: calendar)
        let report = report(
            year: 2026,
            starting: CalendarDay(year: 2026, month: 8, day: 9),
            dayCount: FeatureDiscoveryPresentation.minimumLoggedDayCount,
        )

        let presentation = FeatureDiscoveryPresentation(
            report: report,
            selectedYear: report.year,
            referenceDate: referenceDate,
            calendar: calendar,
        )

        #expect(presentation.usesUserData == false)
    }

    @Test func historicalReportKeepsWidgetAndLockScreenOnTheReportDay() throws {
        let calendar = calendar()
        let referenceDate = try referenceDate(in: calendar)
        let report = report(
            year: 2025,
            starting: CalendarDay(year: 2025, month: 1, day: 1),
            dayCount: FeatureDiscoveryPresentation.minimumLoggedDayCount,
        )

        let presentation = FeatureDiscoveryPresentation(
            report: report,
            selectedYear: report.year,
            referenceDate: referenceDate,
            calendar: calendar,
        )
        let snapshotDay = CalendarDay(from: presentation.widgetSnapshot.day, in: calendar)
        let lockScreenComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: presentation.lockScreenDate,
        )

        #expect(presentation.widgetSnapshot.year == snapshotDay.year)
        #expect(snapshotDay == CalendarDay(year: 2025, month: 1, day: 14))
        #expect(lockScreenComponents.year == 2025)
        #expect(lockScreenComponents.month == 1)
        #expect(lockScreenComponents.day == 14)
        #expect(lockScreenComponents.hour == 13)
        #expect(lockScreenComponents.minute == 45)
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func referenceDate(in calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 8,
            hour: 13,
            minute: 45,
        )))
    }

    private func report(
        year: Int,
        starting firstDay: CalendarDay,
        dayCount: Int,
    ) -> YearReport {
        let days = (0 ..< dayCount).map { offset in
            DayPresence(day: firstDay.adding(days: offset), regions: [.california])
        }
        return YearReport(year: year, days: days, totals: [.california: dayCount])
    }
}
