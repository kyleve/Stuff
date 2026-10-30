import AccessibilitySnapshotParser
import BroadwayCore
import BroadwayUI
import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
@Suite(.serialized)
struct CalendarContentViewTests {
    @Test(arguments: [false, true])
    func zoomReturnsToTheSelectedMonthAndEstimate(reduceMotion: Bool) async throws {
        let root = NavigationStack {
            CalendarContentView(
                report: PreviewSupport.plannedStayYearReportModel(
                    plannedThroughDay: CalendarDay(year: PreviewSupport.year, month: 11, day: 15),
                ),
                initialMode: .overview,
            )
            .bTraitOverrides { _, overrides in
                overrides.accessibility = BAccessibility(isReduceMotionEnabled: reduceMotion)
            }
        }
        .whereBroadwayRoot()

        try await show(UIHostingController(rootView: root)) { host in
            host.view.window?.layer.speed = 1
            try await waitForCalendar("overview to load") {
                element("November", in: host.view) != nil && isEnabled("Show Months", in: host.view)
            }
            for iteration in 0 ..< 6 {
                try activate(#require(element("November", in: host.view)))
                if !reduceMotion {
                    try await waitForCalendar("month transition to start") {
                        element("Show Year", in: host.view)?.accessibilityTraits
                            .contains(.notEnabled) == true
                    }
                }
                try await waitForCalendar("November to expand on iteration \(iteration)") {
                    isEnabled("Show Year", in: host.view)
                        && isVisible("November", in: host.view, expanded: true)
                }
                try activate(#require(element("Show Year", in: host.view)))
                if !reduceMotion {
                    try await waitForCalendar("overview transition to start") {
                        element("Show Months", in: host.view)?.accessibilityTraits
                            .contains(.notEnabled) == true
                    }
                }
                try await waitForCalendar("year overview to return") {
                    isEnabled("Show Months", in: host.view)
                        && isVisible("November", in: host.view, expanded: false)
                }
            }
            try activate(#require(element("Estimated Time", in: host.view)))
            try await waitForCalendar("estimate to expand") {
                isEnabled("Show Year", in: host.view)
                    && element("Estimated Time", in: host.view)?.accessibilityFrame
                    .intersects(host.view.convert(host.view.bounds, to: nil)) == true
            }
        }
    }

    private func element(_ prefix: String, in view: UIView) -> NSObject? {
        accessibilityObjects(in: view).first { $0.accessibilityLabel?.hasPrefix(prefix) == true }
    }

    private func isEnabled(_ label: String, in view: UIView) -> Bool {
        guard let element = element(label, in: view) else { return false }
        return !element.accessibilityTraits.contains(.notEnabled)
    }

    private func isVisible(_ label: String, in view: UIView, expanded: Bool) -> Bool {
        guard let frame = element(label, in: view)?.accessibilityFrame else { return false }
        return frame.intersects(view.convert(view.bounds, to: nil))
            &&
            (expanded ? frame.width > view.bounds.width / 2 : frame.width < view.bounds
                .width / 2)
    }

    private func activate(_ element: NSObject) throws {
        if let control = element as? UIControl {
            control.sendActions(for: .touchUpInside)
        } else {
            try #require(element.accessibilityActivate())
        }
    }

    private func waitForCalendar(_ condition: String, _ predicate: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while !predicate() {
            try Task.checkCancellation()
            guard clock.now < deadline
            else { throw TestHostError("Timed out waiting for \(condition)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func accessibilityObjects(in root: NSObject) -> [NSObject] {
        var visited: Set<ObjectIdentifier> = []
        func visit(_ object: NSObject) -> [NSObject] {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
            var result = [object]
            if let view = object as? UIView {
                result += view.subviews.flatMap(visit)
            }
            let count = object.accessibilityElementCount()
            if count > 0, count < 10000 {
                for index in 0 ..< count {
                    if let child = object.accessibilityElement(at: index) as? NSObject {
                        result += visit(child)
                    }
                }
            }
            return result
        }
        return visit(root)
    }

    @Test func repeatedLinkedSelectionExpandsOverviewAndKeepsMonthTarget() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let history = HistoryNavigationModel()
        let presentation = history.calendar.presentation(
            report: report,
            initialMode: .overview,
            persistenceKey: .year,
        )
        let month = CalendarDay(year: report.selectedYear, month: 2, day: 1)
        let host = UIHostingController(rootView: CalendarContentView(
            report: report,
            history: history,
            persistenceKey: .year,
        ).whereBroadwayRoot())
        try await show(host) { _ in
            try await waitForAsync { presentation.year == report.selectedYear }
            for _ in 0 ..< 2 {
                history.select(month: month, dateCalendar: report.calendar)
                try await waitForAsync {
                    history.calendar.pendingReveal == nil && presentation.mode == .detail
                        && isVisible("February", in: host.view, expanded: true)
                }
                presentation.toggle()
                #expect(presentation.mode == .overview)
            }
        }
    }

    @Test func regionZoomPreferencesRemainIndependentInRetainedNavigation() {
        let report = PreviewSupport.loadedYearReportModel()
        let navigation = CalendarNavigationModel()
        let california = navigation.presentation(
            report: report,
            initialMode: .detail,
            persistenceKey: .region(.california),
        )
        let newYork = navigation.presentation(
            report: report,
            initialMode: .detail,
            persistenceKey: .region(.newYork),
        )
        california.toggle()
        #expect(california.mode == .overview)
        #expect(newYork.mode == .detail)
        #expect(navigation.presentation(
            report: report,
            initialMode: .detail,
            persistenceKey: .region(.california),
        ) === california)
    }

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
            try await waitForAsync {
                navigation.initiallyPositionedYear == previousYear
                    && isVisible("December", in: host.view, expanded: true)
            }
            #expect(navigation.scrollPosition.viewID(type: CalendarDay.self) == CalendarDay(
                year: previousYear,
                month: 12,
                day: 1,
            ))
        }
    }

    @Test func aRemountedCalendarPreservesTheInitialEstimateAlignment() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let navigation = CalendarNavigationModel()
        let first = UIHostingController(rootView: CalendarContentView(
            report: report,
            navigation: navigation,
        ).whereBroadwayRoot())
        var initialBottom: CGFloat?
        try await show(first) { _ in
            try await waitForCalendar("initial estimate to reach the viewport bottom") {
                guard let frame = element("Planned stays", in: first.view)?.accessibilityFrame
                else { return false }
                let viewport = first.view.convert(first.view.bounds, to: nil)
                return viewport.contains(frame) && frame.minY > viewport.midY
            }
            initialBottom = element("Planned stays", in: first.view)?.accessibilityFrame.maxY
        }
        let expectedBottom = try #require(initialBottom)
        let second = UIHostingController(rootView: CalendarContentView(
            report: report,
            navigation: navigation,
        ).whereBroadwayRoot())
        try await show(second) { _ in
            try await waitForCalendar("remounted estimate to retain its bottom alignment") {
                guard let bottom = element("Planned stays", in: second.view)?.accessibilityFrame
                    .maxY
                else { return false }
                return abs(bottom - expectedBottom) <= 1
            }
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
        navigation.presentation(report: report, initialMode: .detail, persistenceKey: nil)
            .remember(.month(browsed))
        let second = UIHostingController(rootView: CalendarContentView(
            report: report,
            navigation: navigation,
        )
        .whereBroadwayRoot())
        try await show(second) { _ in
            try await waitForAsync {
                isVisible("February", in: second.view, expanded: true)
            }
            #expect(scene.locations.calendar.initiallyPositionedYear == nil)
        }
    }
}
