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

    // MARK: - Lock-screen accessories

    @Test func inlineAccessoryHostsWithRegionsAndEmpty() throws {
        let loaded = TodayInlineAccessoryView(snapshot: Self.snapshot(
            dayRegions: [.california, .newYork],
            totals: [.california: 132, .newYork: 41],
        ))
        try show(UIHostingController(rootView: loaded)) { hosted in
            #expect(hosted.view != nil)
        }
        let empty = TodayInlineAccessoryView(snapshot: Self.snapshot(dayRegions: [], totals: [:]))
        try show(UIHostingController(rootView: empty)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func circularAccessoryHostsWithRegionsAndEmpty() throws {
        let multi = TodayCircularAccessoryView(snapshot: Self.snapshot(
            dayRegions: [.california, .newYork],
            totals: [.california: 132, .newYork: 41],
        ))
        try show(UIHostingController(rootView: multi)) { hosted in
            #expect(hosted.view != nil)
        }
        let empty = TodayCircularAccessoryView(snapshot: Self.snapshot(dayRegions: [], totals: [:]))
        try show(UIHostingController(rootView: empty)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func rectangularAccessoryHostsRankedRowsAndEmpty() throws {
        let ranked = YearTotalsRectangularAccessoryView(snapshot: Self.snapshot(
            dayRegions: [.california],
            totals: [.california: 132, .newYork: 41, .canada: 9, .other: 2],
        ))
        try show(UIHostingController(rootView: ranked)) { hosted in
            #expect(hosted.view != nil)
        }
        let empty = YearTotalsRectangularAccessoryView(
            snapshot: Self.snapshot(dayRegions: [], totals: [:]),
        )
        try show(UIHostingController(rootView: empty)) { hosted in
            #expect(hosted.view != nil)
        }
    }

    @Test func rankedTotalsOrderAndCapMatchTheApp() {
        let snapshot = Self.snapshot(
            dayRegions: [],
            totals: [.california: 132, .newYork: 41, .canada: 9, .europeanUnion: 4, .other: 2],
        )
        let ranked = snapshot.rankedTotals(maxRows: 3)
        #expect(ranked.map(\.region) == [.california, .newYork, .canada])
        #expect(ranked.map(\.days) == [132, 41, 9])
    }

    @Test func orderedDayRegionsFollowDeclarationOrder() {
        let snapshot = Self.snapshot(
            dayRegions: [.other, .california, .canada],
            totals: [:],
        )
        #expect(snapshot.orderedDayRegions == [.california, .canada, .other])
    }
}
