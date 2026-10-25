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
            for _ in 0 ..< 3 {
                try activate(#require(element("November", in: host.view)))
                if !reduceMotion {
                    try await waitForCalendar("month transition to start") {
                        element("Show Year", in: host.view)?.accessibilityTraits
                            .contains(.notEnabled) == true
                    }
                }
                try await waitForCalendar("November to expand") {
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
}
