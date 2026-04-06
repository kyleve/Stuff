//
//  XCTestCaseAdditions.swift
//  BroadwayTesting
//

import UIKit

struct ShowError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

/// Shows a view controller in the test host application's window for the
/// duration of `perform`. The view controller is added as a child of
/// the host's root view controller and its view is placed in the window,
/// triggering the full UIKit appearance lifecycle (`viewIsAppearing`, etc.).
///
/// After `perform` returns (or throws), the view controller is removed
/// from the hierarchy automatically.
@MainActor
public func show<ViewController: UIViewController>(
    _ viewController: ViewController,
    loadAndPlaceView: Bool = true,
    perform test: (ViewController) throws -> Void,
) throws {
    guard let rootVC = UIApplication.shared.delegate?.window??.rootViewController else {
        throw ShowError("No root view controller in test host.")
    }

    rootVC.view.window?.layer.speed = 100
    rootVC.addChild(viewController)
    viewController.didMove(toParent: rootVC)

    if loadAndPlaceView {
        viewController.view.frame = rootVC.view.bounds
        rootVC.view.addSubview(viewController.view)
        viewController.view.layoutIfNeeded()
    }

    defer {
        if loadAndPlaceView {
            viewController.view.removeFromSuperview()
        }
        viewController.willMove(toParent: nil)
        viewController.removeFromParent()
        rootVC.view.window?.layer.speed = 1
    }

    try autoreleasepool {
        try test(viewController)
    }
}

// MARK: - Run Loop Helpers

@MainActor
public func waitFor(timeout: TimeInterval = 10.0, predicate: () -> Bool) throws {
    let runloop = RunLoop.main
    let deadline = Date(timeIntervalSinceNow: timeout)

    while Date() < deadline {
        if predicate() {
            return
        }

        runloop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
    }

    throw WaitError("waitFor timed out waiting for a check to pass.")
}

@MainActor
public func waitFor(timeout: TimeInterval = 10.0, block: (() -> Void) -> Void) throws {
    var isDone = false

    try waitFor(timeout: timeout, predicate: {
        block { isDone = true }
        return isDone
    })
}

@MainActor
public func waitForOneRunloop() {
    let runloop = RunLoop.main
    runloop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
}

@MainActor
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

struct WaitError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

// MARK: - UIView Helpers

extension UIView {
    public var recursiveDescription: String {
        value(forKey: "recursiveDescription") as! String
    }
}
