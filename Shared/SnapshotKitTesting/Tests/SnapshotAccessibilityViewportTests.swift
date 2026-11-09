@testable import SnapshotKitTesting
import TestHostSupport
import Testing
import UIKit

@MainActor
struct SnapshotAccessibilityViewportTests {
    @Test(arguments: [false, true])
    func nativeBarListsRestoreAfterCapture(throwsDuringCapture: Bool) async throws {
        let host = UIViewController()
        try await show(host) { controller in
            let window = try #require(controller.view.window)
            let scene = try #require(window.windowScene)
            let originalFrame = window.frame
            defer { window.frame = originalFrame }
            let size = CGSize(
                width: scene.effectiveGeometry.coordinateSpace.bounds.width + 300,
                height: scene.effectiveGeometry.coordinateSpace.bounds.height,
            )
            window.frame.size = size
            controller.view.frame = CGRect(origin: .zero, size: size)

            let subject = UIViewController()
            subject.view.frame = controller.view.bounds
            controller.addChild(subject)
            controller.view.addSubview(subject.view)
            subject.didMove(toParent: controller)
            for (index, title) in ["Sidebar", "Calendar"].enumerated() {
                let navigation = navigationController(title: title)
                navigation.view.frame = CGRect(
                    x: CGFloat(index) * size.width / 2,
                    y: 0,
                    width: size.width / 2,
                    height: size.height,
                )
                subject.addChild(navigation)
                subject.view.addSubview(navigation.view)
                navigation.didMove(toParent: subject)
            }
            let unrelated = navigationController(title: "Unrelated")
            unrelated.view.frame = CGRect(x: 0, y: 300, width: size.width, height: 300)
            controller.addChild(unrelated)
            controller.view.addSubview(unrelated.view)
            unrelated.didMove(toParent: controller)
            let pathView = ScreenPathView(frame: CGRect(x: 30, y: 200, width: 90, height: 60))
            controller.view.addSubview(pathView)
            try await waitForAsync {
                navigationBars(in: subject.view).count == 2
                    && navigationBars(in: unrelated.view).count == 1
                    && navigationBars(in: subject.view)
                    .contains { labels(in: $0).contains("Planning") }
                    && navigationBars(in: unrelated.view)
                    .contains { labels(in: $0).contains("Unrelated") }
            }
            let bars = navigationBars(in: subject.view)
            let unrelatedBar = try #require(navigationBars(in: unrelated.view).first)
            let before = bars.map { labels(in: $0) }
            // UIKit versions differ in whether off-screen bar items are filtered.
            // Both paths must restore automatic getters and preserve coordinates.
            #expect(before.contains { $0.contains("Planning") })
            let unrelatedBefore = labels(in: unrelatedBar)
            let frames = bars.map(\.frame)
            let transform = window.transform
            let center = window.center
            let path = try #require(pathView.accessibilityPath).bounds

            do {
                try SnapshotAccessibilityViewport.withUnclippedNavigationBars(in: subject.view) {
                    for bar in bars {
                        #expect(labels(in: bar).contains("Planning"))
                        #expect(labels(in: bar).contains("Overview"))
                    }
                    #expect(labels(in: unrelatedBar) == unrelatedBefore)
                    #expect(bars.map(\.frame) == frames)
                    #expect(window.transform == transform)
                    #expect(window.center == center)
                    #expect(pathView.accessibilityPath?.bounds == path)
                    if throwsDuringCapture { throw CaptureFailure.expected }
                }
                #expect(!throwsDuringCapture)
            } catch CaptureFailure.expected {
                #expect(throwsDuringCapture)
            }
            #expect(bars.map { labels(in: $0) } == before)
            #expect(window.transform == transform)
            #expect(window.center == center)
            #expect(bars.map(\.frame) == frames)

            // A restored stored list would pass the equality above but fail this:
            // UIKit must recompute its elements after the real item changes.
            let bar = try #require(bars.first { labels(in: $0).contains("Planning") })
            bar.topItem?.rightBarButtonItems = [UIBarButtonItem(
                title: "Replacement",
                style: .plain,
                target: nil,
                action: nil,
            )]
            bar.frame.size.width = scene.effectiveGeometry.coordinateSpace.bounds.width
            bar.setNeedsLayout()
            bar.layoutIfNeeded()
            #expect(labels(in: bar).contains("Replacement"))
            #expect(!labels(in: bar).contains("Planning"))
        }
    }

    private func navigationController(title: String) -> UINavigationController {
        let content = UIViewController()
        content.view.backgroundColor = .white
        content.navigationItem.title = title
        content.navigationItem.rightBarButtonItems = ["Planning", "Overview"].map {
            UIBarButtonItem(title: $0, style: .plain, target: nil, action: nil)
        }
        return UINavigationController(rootViewController: content)
    }

    private func navigationBars(in view: UIView) -> [UINavigationBar] {
        (view as? UINavigationBar).map { [$0] } ?? view.subviews.flatMap { navigationBars(in: $0) }
    }

    private func labels(in bar: UINavigationBar) -> [String] {
        (bar.accessibilityElements as? [NSObject] ?? []).compactMap(\.accessibilityLabel)
    }

    private enum CaptureFailure: Error { case expected }
}

@MainActor
private final class ScreenPathView: UIView {
    override var accessibilityPath: UIBezierPath? {
        get { UIBezierPath(rect: convert(bounds, to: nil)) }
        set { super.accessibilityPath = newValue }
    }
}
