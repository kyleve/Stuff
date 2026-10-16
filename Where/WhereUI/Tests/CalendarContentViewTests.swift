import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct CalendarContentViewTests {
    @Test func mountedCalendarPositionsAfterTheNewYearsMonthsArrive() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let navigation = CalendarNavigationModel()
        let host = UIHostingController(rootView: CalendarContentView(
            report: report,
            navigation: navigation,
        )
        .whereBroadwayRoot())
        try await show(host) { _ in
            try await waitForAsync { navigation.initiallyPositionedYear == report.selectedYear }
            let previousYear = report.selectedYear - 1
            await report.select(year: previousYear)
            try await waitForAsync { navigation.initiallyPositionedYear == previousYear }
            #expect(navigation.scrollPosition.viewID(type: CalendarDay.self) == CalendarDay(
                year: previousYear,
                month: 12,
                day: 1,
            ))
        }
    }

    @Test func aRemountedCalendarUsesTheSceneAnchor() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let scene = SceneNavigationModel()
        let navigation = scene.year.calendar
        let browsed = CalendarDay(year: report.selectedYear, month: 2, day: 1)
        let first = UIHostingController(rootView: CalendarContentView(
            report: report,
            navigation: navigation,
        )
        .whereBroadwayRoot())
        try await show(first) { _ in
            try await waitForAsync {
                navigation.initiallyPositionedYear == report.selectedYear
            }
        }
        navigation.recordVisibleMonths([browsed])
        let second = UIHostingController(rootView: CalendarContentView(
            report: report,
            navigation: navigation,
        )
        .whereBroadwayRoot())
        try await show(second) { _ in
            try await waitForAsync {
                navigation.scrollPosition.viewID(type: CalendarDay.self) == browsed
            }
            #expect(scene.locations.calendar.initiallyPositionedYear == nil)
        }
    }
}
