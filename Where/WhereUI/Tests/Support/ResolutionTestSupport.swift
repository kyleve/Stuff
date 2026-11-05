import Foundation
import TestHostSupport
import Testing
import UIKit
import WhereCore
@testable import WhereUI

/// Holds only the first completed scan so a newer request can finish before it.
@MainActor
final class ResolutionScanSuspension {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspendFirst() async {
        guard !entered else { return }
        await withCheckedContinuation {
            continuation = $0
            entered = true
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
func resolutionAccessibilityObjects(in root: NSObject) -> [NSObject] {
    var visited: Set<ObjectIdentifier> = []
    func visit(_ object: NSObject) -> [NSObject] {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
        var result = [object]
        if let view = object as? UIView { result += view.subviews.flatMap(visit) }
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

@MainActor
func resolutionElement(_ identifier: String, in root: NSObject) -> NSObject? {
    resolutionAccessibilityObjects(in: root).first {
        guard $0.responds(to: NSSelectorFromString("accessibilityIdentifier")) else { return false }
        return $0.value(forKey: "accessibilityIdentifier") as? String == identifier
    }
}

@MainActor
func activateResolutionElement(_ element: NSObject) throws {
    func control(in view: UIView) -> UIControl? {
        if let control = view as? UIControl { return control }
        return view.subviews.lazy.compactMap { control(in: $0) }.first
    }
    if let view = element as? UIView, let control = control(in: view) {
        control.sendActions(for: .touchUpInside)
    } else {
        try #require(
            element.accessibilityActivate(),
            "Could not activate \(type(of: element)): \(element.accessibilityLabel ?? "unlabelled")",
        )
    }
}

@MainActor
func waitForResolutionView(_ condition: String, _ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !predicate() {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw TestHostError(condition) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
func resolutionPresentedController(in controller: UIViewController) -> UIViewController? {
    if let presented = controller.presentedViewController {
        return resolutionPresentedController(in: presented) ?? presented
    }
    return controller.children.lazy.compactMap { resolutionPresentedController(in: $0) }.first
}

@MainActor
func resolutionNavigationController(in controller: UIViewController) -> UINavigationController? {
    if let navigation = controller as? UINavigationController { return navigation }
    return controller.children.lazy.compactMap { resolutionNavigationController(in: $0) }.first
}
