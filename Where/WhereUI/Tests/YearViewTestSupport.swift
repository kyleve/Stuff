import TestHostSupport
import Testing
import UIKit

/// Finds the native pager and its visible vertical page without relying on SwiftUI's private class
/// names.
@MainActor
enum YearViewTestSupport {
    static func selectPage(_ index: Int, in pager: UIScrollView) {
        pager.setContentOffset(
            CGPoint(x: CGFloat(index) * pager.bounds.width, y: 0),
            animated: false,
        )
        pager.delegate?.scrollViewDidEndDecelerating?(pager)
    }

    static func title(in view: UIView) -> String? {
        if let bar = view as? UINavigationBar { return bar.topItem?.title }
        return view.subviews.lazy.compactMap { title(in: $0) }.first
    }

    static func trailingButtonCount(in view: UIView) -> Int? {
        if let bar = view as? UINavigationBar, let item = bar.topItem {
            return (item.rightBarButtonItems?.count ?? 0)
                + item.trailingItemGroups.reduce(0) { $0 + $1.barButtonItems.count }
        }
        return view.subviews.lazy.compactMap { trailingButtonCount(in: $0) }.first
    }

    static func pager(in root: UIView) -> UIScrollView? {
        scrollViews(in: root).first {
            $0.isPagingEnabled && $0.contentSize.width > $0.bounds.width
                && receivesTouches($0, in: root)
        }
    }

    static func visibleVerticalScrollView(in root: UIView) -> UIScrollView? {
        scrollViews(in: root).first { scroll in
            scroll.contentSize.height > scroll.bounds.height && receivesTouches(scroll, in: root)
        }
    }

    private static func receivesTouches(_ view: UIView, in root: UIView) -> Bool {
        let visibleFrame = view.convert(view.bounds, to: root).intersection(root.bounds)
        guard visibleFrame.width > root.bounds.width * 0.9 else { return false }
        // TabView can retain inactive pages in the UIKit tree.
        // Only the scroll view receiving touches belongs to the visible page.
        var hit = root.hitTest(CGPoint(x: visibleFrame.midX, y: visibleFrame.midY), with: nil)
        while let candidate = hit {
            if candidate === view { return true }
            hit = candidate.superview
        }
        return false
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        let own = (view as? UIScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { scrollViews(in: $0) }
    }

    static func attachScreenshot(of view: UIView) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            Attachment.record(data, named: "Your Year.png")
        } else {
            Issue.record("Could not encode the Your Year viewport")
        }
        Attachment.record(scrollViews(in: view).map {
            "\(ObjectIdentifier($0)) \(type(of: $0)): frame=\($0.convert($0.bounds, to: view)), offset=\($0.contentOffset), size=\($0.contentSize)"
        }.joined(separator: "\n"), named: "Scroll views.txt")
        Attachment.record(title(in: view) ?? "No title", named: "Navigation title.txt")
    }

    static func wait(line: UInt = #line, _ predicate: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while !predicate() {
            guard clock.now < deadline else {
                throw TestHostError("Timed out waiting for Your Year at test line \(line)")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
