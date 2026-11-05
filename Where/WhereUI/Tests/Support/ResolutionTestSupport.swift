import Foundation
import TestHostSupport
import Testing
import UIKit
import WhereCore
@testable import WhereUI

/// Dismisses sheets from their actual presenting child before TestHostSupport removes it.
/// Dismissing the host window's root does not close a child hosting controller's sheets.
@MainActor
func showResolution<Controller: UIViewController>(
    _ controller: Controller,
    perform test: (Controller) async throws -> Void,
) async throws {
    try await show(controller) { host in
        do {
            try await test(host)
        } catch {
            await dismissResolutionPresentations(in: host)
            throw error
        }
        await dismissResolutionPresentations(in: host)
    }
}

@MainActor
private func dismissResolutionPresentations(in controller: UIViewController) async {
    if controller.presentedViewController != nil {
        await withCheckedContinuation { continuation in
            controller.dismiss(animated: false) { continuation.resume() }
        }
    }
    for child in controller.children {
        await dismissResolutionPresentations(in: child)
    }
}

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
    resolutionAccessibilityObjects(in: root, skippingHiddenViews: false)
}

@MainActor
private func resolutionAccessibilityObjects(
    in root: NSObject,
    skippingHiddenViews: Bool,
) -> [NSObject] {
    var visited: Set<ObjectIdentifier> = []
    func visit(_ object: NSObject) -> [NSObject] {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
        if skippingHiddenViews, let view = object as? UIView,
           view.isHidden || view.alpha <= 0.01 { return [] }
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
func resolutionEnabledElement(_ identifier: String, in root: NSObject) -> NSObject? {
    guard let element = resolutionElement(identifier, in: root),
          !element.accessibilityTraits.contains(.notEnabled)
    else { return nil }
    return element
}

/// A List can retain removed cells in its reuse hierarchy after the visible row disappears.
@MainActor
func resolutionVisibleElement(_ identifier: String, in root: UIView) -> NSObject? {
    resolutionAccessibilityObjects(in: root, skippingHiddenViews: true).first { element in
        guard element.responds(to: NSSelectorFromString("accessibilityIdentifier")),
              element.value(forKey: "accessibilityIdentifier") as? String == identifier
        else { return false }
        let frame = element.accessibilityFrame
        return !frame.isEmpty && frame.intersects(root.convert(root.bounds, to: nil))
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
        let activated = element.accessibilityActivate()
        try #require(
            activated,
            "Could not activate \(type(of: element)): \(element.accessibilityLabel ?? "unlabelled")",
        )
    }
}

@MainActor
func waitForResolutionView(_ condition: String, _ predicate: () throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while try !predicate() {
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

/// Scrolls the live Form/List, keeping interaction assertions on the production hierarchy.
@MainActor
func scrollResolutionList(in root: UIView, toBottom: Bool) throws {
    let scroll = try #require(resolutionAccessibilityObjects(in: root)
        .compactMap { $0 as? UIScrollView }.first {
            $0 is UICollectionView || $0 is UITableView
        })
    scroll.layoutIfNeeded()
    let top = -scroll.adjustedContentInset.top
    let bottom = max(
        top,
        scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom,
    )
    scroll.setContentOffset(
        CGPoint(x: scroll.contentOffset.x, y: toBottom ? bottom : top),
        animated: false,
    )
    scroll.layoutIfNeeded()
}

/// Advances through a lazy Form/List until the requested production row is available.
/// This also reaches middle rows when neither the top nor bottom viewport contains them.
@MainActor
func revealResolutionElement(_ identifier: String, in root: UIView) async throws {
    try scrollResolutionList(in: root, toBottom: false)
    try await waitForResolutionView(identifier) {
        if resolutionElement(identifier, in: root) != nil { return true }
        let scroll = try #require(resolutionAccessibilityObjects(in: root)
            .compactMap { $0 as? UIScrollView }.first {
                $0 is UICollectionView || $0 is UITableView
            })
        let bottom = max(
            -scroll.adjustedContentInset.top,
            scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom,
        )
        let next = min(bottom, scroll.contentOffset.y + scroll.bounds.height / 2)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: next), animated: false)
        scroll.layoutIfNeeded()
        return false
    }
}
