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
        HostedAccessibility.objects(in: view)
            .first { $0.accessibilityLabel?.hasPrefix(prefix) == true }
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

    @Test func overviewAndTabletopDoNotReplaceTheForecastAnchor() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let fixture = CalendarPresentationFixture()
        let reveals = CalendarRevealTestSupport()
        let host = UIHostingController(rootView: CalendarPresentationHarness(
            fixture: fixture,
            report: report,
            reveals: reveals,
        ))
        try await show(host) { controller in
            controller.view.window?.layer.speed = 1
            try await waitForCalendar("initial forecast") {
                guard let frame = element("Planned stays", in: host.view)?.accessibilityFrame
                else { return false }
                let bottom = host.view.convert(host.view.safeAreaLayoutGuide.layoutFrame, to: nil)
                    .maxY
                    - WhereStylesheet.default.locationForecast.padding
                return abs(frame.maxY - bottom) < 1
            }
            let initialBottom = try #require(element("Planned stays", in: host.view)?
                .accessibilityFrame.maxY)
            try activate(#require(element("Show Year", in: host.view)))
            try await waitForCalendar("overview transition starts") {
                element("Show Months", in: host.view)?.accessibilityTraits
                    .contains(.notEnabled) == true
            }
            try await waitForCalendar("overview") {
                isEnabled("Show Months", in: host.view) && isVisible(
                    "July",
                    in: host.view,
                    expanded: false,
                )
            }
            try activate(#require(element("Show Months", in: host.view)))
            try await waitForCalendar("detail transition starts") {
                element("Show Year", in: host.view)?.accessibilityTraits
                    .contains(.notEnabled) == true
            }
            do {
                try await waitForCalendar("forecast after overview") {
                    isEnabled("Show Year", in: host.view) && element("Planned stays", in: host.view)
                        .map { abs($0.accessibilityFrame.maxY - initialBottom) < 1 } == true
                }
            } catch {
                throw TestHostError(
                    "\(error); expectedBottom=\(initialBottom), frame=\(String(describing: element("Planned stays", in: host.view)?.accessibilityFrame)), enabled=\(isEnabled("Show Year", in: host.view))",
                )
            }
            fixture.showsTabletop = true
            try await waitForCalendar("tabletop month") { isVisible(
                "July",
                in: host.view,
                expanded: true,
            ) && element("Planned stays", in: host.view) == nil }
            fixture.showsTabletop = false
            try await waitForCalendar("forecast after tabletop") { element(
                "Planned stays",
                in: host.view,
            ).map { abs($0.accessibilityFrame.maxY - initialBottom) < 1 } == true }
        }
    }

    @Test func theUnselectedLocationsCalendarKeepsItsSessionOnlyZoomMode() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let state = AdaptivePaneHostState()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            LocationsView(report: report)
        }.bScrollRestorationScope())
        host.safeAreaRegions = []
        try await show(host) { controller in
            try await AdaptivePaneTestSupport.resize(
                controller,
                state: state,
                to: .innerLandscape,
            )
            try await waitForCalendar("unselected detail calendar") { isEnabled(
                "Show Year",
                in: host.view,
            ) }
            try activate(#require(element("Show Year", in: host.view)))
            try await waitForCalendar("session-only overview") { isEnabled(
                "Show Months",
                in: host.view,
            ) }
            try await AdaptivePaneTestSupport.resize(controller, state: state, to: .tabletop)
            try await waitForCalendar("tabletop calendar") { isVisible(
                "July",
                in: host.view,
                expanded: true,
            ) }
            try await AdaptivePaneTestSupport.resize(
                controller,
                state: state,
                to: .innerLandscape,
            )
            try await waitForCalendar("session-only overview after folding") { isEnabled(
                "Show Months",
                in: host.view,
            ) }
            #expect(report.preferences.calendarOverview(forKey: .year) == nil)
        }
    }

    @Test func changingRegionsResetsTheAnchorButKeepsEachZoomPreference() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        report.preferences.setCalendarOverview(true, forKey: .region(.california))
        report.preferences.setCalendarOverview(false, forKey: .region(.newYork))
        let navigation = LocationsView.Navigation()
        navigation.select(region: .california)
        let state = AdaptivePaneHostState()
        let host = UIHostingController(rootView: AdaptivePaneHostedSurface(state: state) {
            LocationsView(report: report, navigation: navigation)
        }.bScrollRestorationScope())
        host.safeAreaRegions = []
        try await show(host) { controller in
            try await AdaptivePaneTestSupport.resize(
                controller,
                state: state,
                to: .innerLandscape,
            )
            try await waitForCalendar("California overview") { isEnabled(
                "Show Months",
                in: host.view,
            ) }
            try activate(#require(element("March", in: host.view)))
            try await waitForCalendar("California March") {
                isEnabled("Show Year", in: host.view) && isVisible(
                    "March",
                    in: host.view,
                    expanded: true,
                )
            }
            try activate(#require(element("Show Year", in: host.view)))
            try await waitForCalendar("saved California overview") { isEnabled(
                "Show Months",
                in: host.view,
            ) }
            navigation.select(region: .newYork)
            try await waitForCalendar("New York detail") {
                isEnabled("Show Year", in: host.view) && isVisible(
                    "July",
                    in: host.view,
                    expanded: true,
                )
            }
            navigation.select(region: .california)
            try await waitForCalendar("restored California overview preference") { isEnabled(
                "Show Months",
                in: host.view,
            ) }
            try activate(#require(element("Show Months", in: host.view)))
            try await waitForCalendar("fresh California context") { isEnabled(
                "Show Year",
                in: host.view,
            ) && isVisible("July", in: host.view, expanded: true) && !isVisible(
                "March",
                in: host.view,
                expanded: true,
            ) }
        }
    }

    @Test func removingTheForecastFallsBackToTheInitialMonth() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let host = UIHostingController(rootView: CalendarContentView(report: report)
            .whereBroadwayRoot().bScrollRestorationScope())
        try await show(host) { _ in
            try await waitForCalendar("initial forecast") {
                element("Planned stays", in: host.view) != nil
            }
            try await report.setEstimatedTimeAndPlanningEnabled(false)
            try await waitForCalendar("fallback after forecast removal") { element(
                "Planned stays",
                in: host.view,
            ) == nil && isVisible("July", in: host.view, expanded: true) }
        }
    }

    @Test func aRevealWaitsForDelayedCalendarData() async throws {
        let store = try TestStore()
        let report = PlanningTestSupport.report(store: store)
        let reveals = CalendarRevealTestSupport()
        let month = CalendarDay(year: report.selectedYear, month: 2, day: 1)
        reveals.select(month: month)
        await store.enableFirstSamplesGate()
        let load = Task { await report.refresh() }
        await store.awaitFirstSamplesCall()
        let host = UIHostingController(rootView: CalendarContentView(
            report: report,
            monthReveal: reveals.binding,
        ).whereBroadwayRoot().bScrollRestorationScope())
        do {
            try await show(host) { _ in
                #expect(reveals.request?.isPending == true)
                await store.releaseFirstSamplesCall()
                await load.value
                try await waitForCalendar("delayed February reveal") {
                    reveals.request?.isPending == false && isVisible(
                        "February",
                        in: host.view,
                        expanded: true,
                    )
                }
            }
        } catch {
            await store.releaseFirstSamplesCall()
            await load.value
            throw error
        }
    }

    @Test func repeatedMonthRevealExpandsOverviewAndKeepsMonthTarget() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let reveals = CalendarRevealTestSupport()
        let month = CalendarDay(year: report.selectedYear, month: 2, day: 1)
        let host = UIHostingController(rootView: NavigationStack {
            CalendarContentView(
                report: report,
                monthReveal: reveals.binding,
                initialMode: .overview,
                persistenceKey: .year,
            )
        }.whereBroadwayRoot().bScrollRestorationScope())
        try await show(host) { _ in
            try await waitForCalendar("overview to load") { isEnabled("Show Months", in: host.view)
            }
            for _ in 0 ..< 2 {
                reveals.select(month: month)
                try await waitForCalendar("explicit February reveal") {
                    reveals.request?.isPending == false
                        && isVisible("February", in: host.view, expanded: true)
                        && isEnabled("Show Year", in: host.view)
                }
                try activate(#require(element("Show Year", in: host.view)))
                try await waitForCalendar("overview after reveal") { isEnabled(
                    "Show Months",
                    in: host.view,
                ) }
            }
        }
    }

    @Test func aConsumedRevealDoesNotReplayOverBrowsingAfterRemount() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let reveals = CalendarRevealTestSupport()
        let capture = ScrollPositionCapture()
        let store = BScrollRestorationStore()
        let february = CalendarDay(year: report.selectedYear, month: 2, day: 1)
        let june = CalendarPresentationState.Target.month(CalendarDay(
            year: report.selectedYear,
            month: 6,
            day: 1,
        ))
        func calendar() -> some View {
            CalendarContentView(report: report, monthReveal: reveals.binding)
                .overlay {
                    ScrollPositionProbe(
                        CalendarContentView.self,
                        role: CalendarContentView.ScrollRole.standalone,
                        context: CalendarContentView.ScrollContext(
                            region: nil,
                            year: report.selectedYear,
                        ),
                        idType: CalendarPresentationState.Target.self,
                        capture: capture,
                    )
                }
                .whereBroadwayRoot()
                .bScrollRestorationScope(store)
        }
        let first = UIHostingController(rootView: calendar())
        try await show(first) { _ in
            reveals.select(month: february)
            try await waitForCalendar("February reveal consumed") {
                reveals.request?.isPending == false && isVisible(
                    "February",
                    in: first.view,
                    expanded: true,
                )
            }
            capture.binding?.wrappedValue.scrollTo(id: june, anchor: .top)
            try await waitForCalendar("independent browsing to June") {
                isVisible("June", in: first.view, expanded: true)
            }
        }
        let requestID = try #require(reveals.request?.id)
        let second = UIHostingController(rootView: calendar())
        try await show(second) { _ in
            try await waitForCalendar("June restored without replaying February") {
                capture.binding?.wrappedValue
                    .viewID(type: CalendarPresentationState.Target.self) == june
                    && isVisible("June", in: second.view, expanded: true)
            }
            #expect(reveals.request?.id == requestID)
            #expect(reveals.request?.isPending == false)
        }
    }

    @Test func mountedCalendarPositionsAfterTheNewYearsMonthsArrive() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let reveals = CalendarRevealTestSupport()
        let host = UIHostingController(rootView: CalendarContentView(
            report: report,
            monthReveal: reveals.binding,
        )
        .whereBroadwayRoot().bScrollRestorationScope())
        try await show(host) { _ in
            try await waitForCalendar("initial forecast") {
                element("Planned stays", in: host.view) != nil
            }
            reveals.select(
                month: CalendarDay(year: report.selectedYear, month: 2, day: 1),
            )
            try await waitForCalendar("February before year change") { isVisible(
                "February",
                in: host.view,
                expanded: true,
            ) }
            await report.select(year: report.selectedYear - 1)
            try await waitForCalendar("December after year change") { isVisible(
                "December",
                in: host.view,
                expanded: true,
            ) }
        }
    }

    @Test func aRemountedCalendarPreservesTheInitialEstimateAlignment() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let store = BScrollRestorationStore()
        let first = UIHostingController(rootView: CalendarContentView(report: report)
            .whereBroadwayRoot().bScrollRestorationScope(store))
        var initialBottom: CGFloat?
        try await show(first) { _ in
            try await waitForCalendar("initial estimate to reach the viewport bottom") {
                guard let frame = element("Planned stays", in: first.view)?.accessibilityFrame
                else { return false }
                let bottom = first.view.convert(first.view.safeAreaLayoutGuide.layoutFrame, to: nil)
                    .maxY
                    - WhereStylesheet.default.locationForecast.padding
                return abs(frame.maxY - bottom) < 1
            }
            initialBottom = element("Planned stays", in: first.view)?.accessibilityFrame.maxY
        }
        let expectedBottom = try #require(initialBottom)
        let second = UIHostingController(rootView: CalendarContentView(report: report)
            .whereBroadwayRoot().bScrollRestorationScope(store))
        try await show(second) { _ in
            try await waitForCalendar("remounted estimate to retain its bottom alignment") {
                guard let bottom = element("Planned stays", in: second.view)?.accessibilityFrame
                    .maxY else { return false }
                return abs(bottom - expectedBottom) <= 1
            }
        }
    }

    @Test func aRemountedCalendarUsesItsRenderedMonthAnchor() async throws {
        let report = PreviewSupport.loadedYearReportModel()
        let reveals = CalendarRevealTestSupport()
        let store = BScrollRestorationStore()
        let first = UIHostingController(rootView: CalendarContentView(
            report: report,
            monthReveal: reveals.binding,
        )
        .whereBroadwayRoot().bScrollRestorationScope(store))
        try await show(first) { _ in
            try await waitForCalendar("initial forecast") { element(
                "Planned stays",
                in: first.view,
            ) != nil }
            reveals.select(
                month: CalendarDay(year: report.selectedYear, month: 2, day: 1),
            )
            try await waitForCalendar("rendered February anchor") { isVisible(
                "February",
                in: first.view,
                expanded: true,
            ) }
        }
        // A new view has no reveal request: only the retained native position can restore
        // February.
        let second = UIHostingController(rootView: CalendarContentView(report: report)
            .whereBroadwayRoot().bScrollRestorationScope(store))
        try await show(second) { _ in
            try await waitForCalendar("restored February anchor") { isVisible(
                "February",
                in: second.view,
                expanded: true,
            ) }
        }
    }
}
