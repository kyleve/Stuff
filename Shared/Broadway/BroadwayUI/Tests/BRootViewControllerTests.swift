import BroadwayCore
@testable import BroadwayUI
import SwiftUI
import Testing
import UIKit

@MainActor struct BRootViewControllerTests {
    // MARK: - Initialization

    @Test("Context traits reflect the live accessibility snapshot")
    func contextHasLiveAccessibility() {
        let vc = BRootViewController(child: UIViewController())
        #expect(vc.context.traits.accessibility == BAccessibility.current())
    }

    @Test("Convenience init wraps SwiftUI content")
    func swiftUIConvenience() {
        let vc = BRootViewController {
            Text("Hello")
        }
        #expect(vc.context.traits.accessibility == BAccessibility.current())
    }

    // MARK: - Child Containment

    @Test("Child is added to parent in init")
    func childAddedInInit() {
        let child = UIViewController()
        let root = BRootViewController(child: child)

        #expect(child.parent === root)
    }

    @Test("Child view is added as subview after loading")
    func childViewEmbedded() {
        let child = UIViewController()
        let root = BRootViewController(child: child)

        root.loadViewIfNeeded()

        #expect(child.view.superview === root.view)
    }

    // MARK: - Trait Propagation

    @Test("Context is written into traitOverrides at init")
    func traitOverrideSet() {
        let vc = BRootViewController(child: UIViewController())
        #expect(vc.traitOverrides.bContext == vc.context)
    }

    @Test("Default bContext on UITraitCollection equals BContext()")
    func defaultTraitCollectionContext() {
        let tc = UITraitCollection()
        #expect(tc.bContext == BContext())
    }

    @Test("Child inherits bContext after layout")
    func childInheritsContext() {
        let child = UIViewController()
        let root = BRootViewController(child: child)
        root.loadViewIfNeeded()
        root.view.layoutIfNeeded()

        #expect(child.traitCollection.bContext == root.context)
    }
}
