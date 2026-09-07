//
//  TestHostSupport.swift
//  TestHostSupport
//

import ObjectiveC
import UIKit

/// Error thrown by the hosting and run-loop helpers.
public struct TestHostError: Error, CustomStringConvertible {
    public var description: String

    public init(_ description: String) {
        self.description = description
    }
}

extension UIWindow {
    /// Marks *the* `StuffTestHost` window that hosted test views should be placed
    /// in. `StuffTestHost`'s `SceneDelegate` sets this on the window it creates;
    /// `hostKeyWindow()` selects the window carrying it.
    ///
    /// Backed by an associated object rather than `accessibilityIdentifier` so
    /// nothing else — a test, an accessibility tool — can stamp over it.
    ///
    /// The key is a **name-interned `Selector`**, which the Objective-C runtime
    /// uniques process-wide. This module is a static library embedded into *every*
    /// image that links it (the `StuffTestHost` app plus each `.xctest` bundle),
    /// so a per-image `static var key` would resolve to a *different* address in
    /// the host image than in a test bundle — the host would write under one key
    /// and the test would read under another, silently finding nothing. A
    /// `Selector` resolves to the same pointer in every image, so a value stamped
    /// from the host is readable from a test bundle. Do not replace it with a
    /// `static var key: UInt8`.
    @MainActor
    public var isMainTestHostWindow: Bool {
        get { (objc_getAssociatedObject(self, Self.isMainTestHostWindowKey) as? Bool) ?? false }
        set {
            objc_setAssociatedObject(
                self,
                Self.isMainTestHostWindowKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC,
            )
        }
    }

    private static let isMainTestHostWindowKey = unsafeBitCast(
        Selector(("stuff_isMainTestHostWindow")),
        to: UnsafeRawPointer.self,
    )
}

/// Returns the `StuffTestHost` window marked `isMainTestHostWindow`, or `nil` if
/// the host scene hasn't connected yet.
///
/// Unlike a "first key window" search, this selects only the host's designated
/// window, so a stray system window (keyboard, text-effects) or a window a test
/// created can never stand in for it.
@MainActor
public func hostKeyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first(where: \.isMainTestHostWindow)
}

/// Shows a view controller in the test host's main window for the duration of
/// `perform`. The view controller is added as a child of the host's root view
/// controller and its view is placed in the window, triggering the full UIKit
/// appearance lifecycle (`viewWillAppear`, `viewIsAppearing`, …).
///
/// Waits (pumping the run loop up to `timeout`) for the host window and its root
/// view controller to exist, so a test that runs before the host scene has
/// connected doesn't spuriously fail. After `perform` returns (or throws), the
/// view controller is removed from the hierarchy automatically.
@MainActor
public func show<ViewController: UIViewController>(
    _ viewController: ViewController,
    loadAndPlaceView: Bool = true,
    timeout: TimeInterval = 10.0,
    perform test: (ViewController) throws -> Void,
) throws {
    let rootVC = try waitForHostRootViewController(timeout: timeout)

    // Restore the animation speed first so a trapping `test` body can't leave the
    // host window animating at 100×.
    defer { rootVC.view.window?.layer.speed = 1 }
    rootVC.view.window?.layer.speed = 100

    // Apple's container contract: addChild → attach the view → didMove(toParent:),
    // torn down in reverse.
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

/// Async-body overload of ``show(_:loadAndPlaceView:timeout:perform:)``.
///
/// Use this form when a hosted view must remain in the hierarchy while the
/// test awaits application or SwiftUI task work.
@MainActor
public func show<ViewController: UIViewController>(
    _ viewController: ViewController,
    loadAndPlaceView: Bool = true,
    timeout: TimeInterval = 10.0,
    perform test: (ViewController) async throws -> Void,
) async throws {
    let rootVC = try waitForHostRootViewController(timeout: timeout)

    defer { rootVC.view.window?.layer.speed = 1 }
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

    try await test(viewController)
}

@MainActor
private func waitForHostRootViewController(timeout: TimeInterval) throws -> UIViewController {
    let deadline = Date(timeIntervalSinceNow: timeout)

    while Date() < deadline {
        if let rootVC = hostKeyWindow()?.rootViewController {
            return rootVC
        }
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
    }

    if let rootVC = hostKeyWindow()?.rootViewController {
        return rootVC
    }

    throw TestHostError(
        "Timed out waiting for the StuffTestHost main window's root view controller.",
    )
}

// MARK: - Run Loop Helpers

/// Drives the run loop until `predicate` holds, or throws once `timeout` elapses.
@MainActor
public func waitFor(timeout: TimeInterval = 10.0, predicate: () -> Bool) throws {
    let deadline = Date(timeIntervalSinceNow: timeout)

    while Date() < deadline {
        if predicate() {
            return
        }
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
    }

    throw TestHostError("waitFor timed out waiting for a check to pass.")
}

/// Drives the run loop up to `timeout` waiting for `condition`, returning whether
/// it ever held. Unlike `waitFor`, a `false` result is a normal outcome — used to
/// assert a branch *never* renders within the budget, without a fixed sleep or
/// hand-rolled run-loop pumping.
@MainActor
public func renders(within timeout: TimeInterval = 0.5, _ condition: () -> Bool) -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
    }
    return condition()
}
