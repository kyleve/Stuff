//
//  XCTestCaseAdditions.swift
//  BroadwayTesting
//
//

import XCTest

extension XCTestCase {
    ///
    /// Call this method to show a view controller in the test host application
    /// during a unit test. The view controller will be the size of host application's device.
    ///
    /// After the test runs, the view controller will be removed from the view hierarchy.
    ///
    /// A test failure will occur if the host application does not exist, or does not have a root view controller.
    ///
    public func show<ViewController: UIViewController>(
        vc viewController: ViewController,
        loadAndPlaceView: Bool = true,
        test: (ViewController) throws -> Void,
    ) rethrows {
        guard let rootVC = UIApplication.shared.delegate?.window??.rootViewController else {
            XCTFail("Cannot present a view controller in a test host that does not have a root window.")
            return
        }

        rootVC.view.window?.layer.speed = 4
        rootVC.addChild(viewController)
        viewController.didMove(toParent: rootVC)

        if loadAndPlaceView {
            viewController.view.frame = rootVC.view.bounds
            viewController.view.layoutIfNeeded()

            rootVC.beginAppearanceTransition(true, animated: false)
            rootVC.view.addSubview(viewController.view)
            rootVC.endAppearanceTransition()
        }

        defer {
            if loadAndPlaceView {
                viewController.beginAppearanceTransition(false, animated: false)
                viewController.view.removeFromSuperview()
                viewController.endAppearanceTransition()
            }

            viewController.willMove(toParent: nil)
            viewController.removeFromParent()
            rootVC.view.window?.layer.speed = 1
        }

        try autoreleasepool {
            try test(viewController)
        }
    }

    public func waitFor(timeout: TimeInterval = 10.0, predicate: () -> Bool) {
        let runloop = RunLoop.main
        let timeout = Date(timeIntervalSinceNow: timeout)

        while Date() < timeout {
            if predicate() {
                return
            }

            runloop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        }

        XCTFail("waitUntil timed out waiting for a check to pass.")
    }

    public func waitFor(timeout: TimeInterval = 10.0, block: (() -> Void) -> Void) {
        var isDone = false

        waitFor(timeout: timeout, predicate: {
            block { isDone = true }
            return isDone
        })
    }

    public func waitForOneRunloop() {
        let runloop = RunLoop.main
        runloop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
    }

    public func determineAverage(for seconds: TimeInterval, using block: () -> Void) {
        let start = Date()

        var iterations = 0

        var lastUpdateDate = Date()

        repeat {
            block()

            iterations += 1

            if Date().timeIntervalSince(lastUpdateDate) >= 1 {
                lastUpdateDate = Date()
                print("Continuing Test: \(iterations) Iterations...")
            }

        } while Date() < start + seconds

        let end = Date()

        let duration = end.timeIntervalSince(start)
        let average = duration / TimeInterval(iterations)

        print("Iterations: \(iterations), Average Time: \(average)")
    }
}

extension UIView {
    public var recursiveDescription: String {
        value(forKey: "recursiveDescription") as! String
    }
}
