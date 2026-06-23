import Foundation
import UIKit

public struct WhereTestingError: Error, CustomStringConvertible {
    public var description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Returns the test host's key window, or the first window in the first scene.
@MainActor
public func hostKeyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first { $0.isKeyWindow }
        ?? UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first
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
    guard let rootVC = hostKeyWindow()?.rootViewController else {
        throw WhereTestingError("No root view controller in test host.")
    }

    defer {
        rootVC.view.window?.layer.speed = 1
    }
    rootVC.view.window?.layer.speed = 100

    rootVC.addChild(viewController)

    if loadAndPlaceView {
        viewController.view.frame = rootVC.view.bounds
        rootVC.view.addSubview(viewController.view)
        viewController.view.layoutIfNeeded()
    }

    viewController.didMove(toParent: rootVC)

    defer {
        viewController.willMove(toParent: nil)
        if loadAndPlaceView {
            viewController.view.removeFromSuperview()
        }
        viewController.removeFromParent()
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

    throw WhereTestingError("waitFor timed out waiting for a check to pass.")
}

@MainActor
public func waitForOneRunloop() {
    let runloop = RunLoop.main
    runloop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
}

/// Drives the run loop up to `timeout` waiting for `condition`, returning
/// whether it ever held. Unlike `waitFor`, a `false` result is a normal
/// outcome — used to assert a branch *never* renders within the budget,
/// without a fixed sleep or hand-rolled run-loop pumping.
@MainActor
public func renders(within timeout: TimeInterval = 0.5, _ condition: () -> Bool) -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
    }
    return condition()
}
