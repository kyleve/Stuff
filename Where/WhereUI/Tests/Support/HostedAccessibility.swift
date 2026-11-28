import AccessibilitySnapshotParser
import TestHostSupport
import UIKit

@MainActor
enum HostedAccessibility {
    static func objects(in root: NSObject) -> [NSObject] {
        hostedAccessibilityObjects(in: root)
    }

    static func isVisible(_ label: String, in view: UIView) -> Bool {
        let viewport = view.convert(view.bounds, to: nil)
        return objects(in: view)
            .contains {
                $0.accessibilityLabel == label && $0.accessibilityFrame.intersects(viewport)
            }
    }
}
