import UIKit

/// Walks UIKit views and virtual accessibility elements in a mounted SwiftUI host.
@MainActor
public func hostedAccessibilityObjects(in root: NSObject) -> [NSObject] {
    var visited: Set<ObjectIdentifier> = []
    @MainActor func visit(_ object: NSObject) -> [NSObject] {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
        var result = [object]
        if let view = object as? UIView {
            result += view.subviews.flatMap(visit)
        }
        let count = object.accessibilityElementCount()
        if count > 0, count < 10000 {
            for index in 0 ..< count {
                if let child = object
                    .accessibilityElement(at: index) as? NSObject
                {
                    result += visit(child)
                }
            }
        }
        return result
    }
    return visit(root)
}

@MainActor
private func accessibilityRoots(in root: UIView) -> [UIView] {
    guard let window = root as? UIWindow, let scene = window.windowScene else { return [root] }
    return scene.windows.reversed().filter { !$0.isHidden && $0.alpha > 0 }
}

/// Waits for a mounted interaction and describes available elements if the step times out.
@MainActor
public func waitForHostedState(
    _ description: String,
    in root: UIView,
    until predicate: () -> Bool,
) async throws {
    do {
        try await waitForAsync(predicate: predicate)
    } catch let error as TestHostError {
        let labels = accessibilityRoots(in: root).flatMap { hostedAccessibilityObjects(in: $0) }
            .compactMap { object -> String? in
                guard let label = object.accessibilityLabel, !label.isEmpty else { return nil }
                return "\(type(of: object))[\(label.prefix(100))]"
            }
        throw TestHostError(
            "\(description). \(error) Mounted elements: \(labels.joined(separator: ", ")).",
        )
    }
}

/// Activates the visible native control matching a label in the mounted host.
@MainActor
public func activateHostedButton(
    _ description: String,
    in root: UIView,
    matching matches: (String) -> Bool,
) async throws {
    var target: NSObject?
    try await waitForHostedState("Find \(description)", in: root) {
        let bounds = root.convert(root.bounds, to: nil)
        target = accessibilityRoots(in: root).lazy.flatMap { hostedAccessibilityObjects(in: $0) }
            .first { object in
                guard let label = object.accessibilityLabel, matches(label) else { return false }
                return object.accessibilityTraits.contains(.button) && object.accessibilityFrame
                    .intersects(bounds)
            }
        return target != nil
    }
    guard let target else { throw TestHostError("The hosted button \(description) disappeared.") }
    if let button = target as? UIButton, button.showsMenuAsPrimaryAction {
        button.performPrimaryAction()
        return
    }
    if target.accessibilityActivate() {
        return
    }
    if let control = target as? UIControl {
        if control.allControlEvents.contains(.primaryActionTriggered) {
            control.sendActions(for: .primaryActionTriggered)
            return
        }
        if control.allControlEvents.contains(.touchUpInside) {
            control.sendActions(for: .touchUpInside)
            return
        }
    }
    throw TestHostError("Could not activate the hosted button \(description).")
}
