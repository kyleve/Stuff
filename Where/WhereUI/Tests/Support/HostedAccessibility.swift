import AccessibilitySnapshotParser
import UIKit

@MainActor
enum HostedAccessibility {
    static func objects(in root: NSObject) -> [NSObject] {
        var visited: Set<ObjectIdentifier> = []
        @MainActor func visit(_ object: NSObject) -> [NSObject] {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
            var result = [object]
            if let view = object as? UIView { result += view.subviews.flatMap(visit) }
            let count = object.accessibilityElementCount()
            if count > 0, count < 10000 {
                for index in 0 ..< count {
                    if let child = object
                        .accessibilityElement(at: index) as? NSObject { result += visit(child) }
                }
            }
            return result
        }
        return visit(root)
    }

    static func isVisible(_ label: String, in view: UIView) -> Bool {
        let viewport = view.convert(view.bounds, to: nil)
        return objects(in: view)
            .contains {
                $0.accessibilityLabel == label && $0.accessibilityFrame.intersects(viewport)
            }
    }
}
