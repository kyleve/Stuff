import SwiftUI
import Testing
import WhereCore
import WhereTesting
@testable import WhereUI

/// Hosts the widget entry views in a real window across their data states
/// (hero single-region, multi-region, ranked totals, and the empties) to
/// confirm they mount without crashing, plus checks the widget strings.
@MainActor
struct WidgetViewsTests {
    private static func snapshot(
        dayRegions: Set<Region>,
        totals: [Region: Int],
    ) -> WidgetSnapshot {
        WidgetSnapshot(day: .now, year: 2026, dayRegions: dayRegions, totals: totals)
    }

    @Test func todayViewHostsWithASingleRegion() throws {
        let view = TodayWidgetView(snapshot: Self.snapshot(
            dayRegions: [.california],
            totals: [.california: 132],
        ))
        try show(UIHostingController(rootView: view)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func todayViewHostsWithMultipleRegions() throws {
        let view = TodayWidgetView(snapshot: Self.snapshot(
            dayRegions: [.california, .newYork],
            totals: [.california: 132, .newYork: 41],
        ))
        try show(UIHostingController(rootView: view)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func todayViewHostsItsEmptyState() throws {
        let view = TodayWidgetView(snapshot: Self.snapshot(dayRegions: [], totals: [:]))
        try show(UIHostingController(rootView: view)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func yearTotalsViewHostsRankedRows() throws {
        let view = YearTotalsWidgetView(snapshot: Self.snapshot(
            dayRegions: [.california],
            totals: [.california: 132, .newYork: 41, .canada: 9, .europeanUnion: 4, .other: 2],
        ))
        try show(UIHostingController(rootView: view)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func yearTotalsViewHostsItsEmptyState() throws {
        let view = YearTotalsWidgetView(snapshot: Self.snapshot(dayRegions: [], totals: [:]))
        try show(UIHostingController(rootView: view)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func widgetStringsResolve() {
        #expect(Strings.widgetTodayTitle == "Today")
        #expect(Strings.widgetTodayEmpty == "Nothing logged yet")
        #expect(Strings.widgetYearTitle(year: 2026) == "Days in 2026")
        #expect(Strings.widgetYearEmpty == "No days logged")
    }
}
