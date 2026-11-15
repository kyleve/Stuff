import AccessibilitySnapshotParser
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Native accessibility actions and controller transitions for themed production views.
@MainActor
enum ThemeInteractionTestSupport {
    static func objects(in root: NSObject) -> [NSObject] {
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

    static func button(_ prefix: String, in root: UIView) -> NSObject? {
        objects(in: root).first {
            $0.accessibilityLabel?.hasPrefix(prefix) == true
                && $0.accessibilityTraits.contains(.button)
        }
    }

    static func activate(_ object: NSObject) throws {
        if let control = object as? UIControl { control.sendActions(for: .touchUpInside) }
        else { try #require(object.accessibilityActivate()) }
    }

    static func navigation(in root: UIViewController) -> UINavigationController? {
        if let navigation = root as? UINavigationController { return navigation }
        return root.children.lazy.compactMap { navigation(in: $0) }.first
    }

    static func presented(in root: UIViewController) -> UIViewController? {
        if let presented = root.presentedViewController { return presented }
        return root.children.lazy.compactMap { presented(in: $0) }.first
    }

    static func wait(_ condition: String, until predicate: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while !predicate() {
            try Task.checkCancellation()
            guard clock.now < deadline else {
                throw TestHostError("Timed out waiting for \(condition)")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

struct ThemeScenePhaseProbe: View {
    let observed: (ScenePhase) -> Void
    @Environment(\.scenePhase) private var phase

    var body: some View {
        // Observe the environment after SwiftUI schedules this phase's tasks. An
        // onChange callback can precede that boundary and coalesce a rapid return.
        Color.clear.task(id: phase) { observed(phase) }
    }
}
