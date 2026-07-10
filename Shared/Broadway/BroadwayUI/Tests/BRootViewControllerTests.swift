import BroadwayCore
import BroadwayTesting
@testable import BroadwayUI
import SwiftUI
import Testing
import UIKit

@MainActor struct BRootViewControllerTests {
    // MARK: - Pre-Setup State

    @Test("Context is nil before entering a valid hierarchy")
    func contextIsNilBeforeSetup() {
        let vc = BRootViewController { UIViewController() }
        #expect(vc.context == nil)
    }

    // MARK: - Post-Setup State

    @Test("Context traits reflect the live accessibility snapshot")
    func contextHasLiveAccessibility() throws {
        try show(BRootViewController { UIViewController() }) { vc in
            #expect(vc.context?.traits.accessibility == BAccessibility.current())
        }
    }

    @Test("Convenience init wraps SwiftUI content")
    func swiftUIConvenience() throws {
        try show(BRootViewController { Text("Hello") }) { vc in
            #expect(vc.context?.traits.accessibility == BAccessibility.current())
        }
    }

    // MARK: - Child Containment

    @Test("Child is added after entering a valid hierarchy")
    func childAddedAfterSetup() throws {
        try show(BRootViewController { UIViewController() }) { root in
            #expect(root.children.count == 1)
            #expect(root.children.first?.parent === root)
        }
    }

    @Test("Child view is a subview after setup")
    func childViewEmbedded() throws {
        try show(BRootViewController { UIViewController() }) { root in
            let child = root.children.first
            #expect(child?.view.superview === root.view)
        }
    }

    // MARK: - Trait Propagation

    @Test("Context is written into traitOverrides after setup")
    func traitOverrideSet() throws {
        try show(BRootViewController { UIViewController() }) { vc in
            #expect(vc.traitOverrides.bContext == vc.context)
        }
    }

    @Test("Default bContext on UITraitCollection has default traits")
    func defaultTraitCollectionContext() {
        let tc = UITraitCollection()
        #expect(tc.bContext.traits.accessibility == BAccessibility())
        #expect(tc.bContext.themes == BThemes())
    }

    @Test("Child inherits bContext after layout")
    func childInheritsContext() throws {
        try show(BRootViewController { UIViewController() }) { root in
            root.view.layoutIfNeeded()
            let child = root.children.first
            #expect(child?.traitCollection.bContext == root.context)
        }
    }

    @Test("Trait override container preserves inherited base traits and themes on screen")
    func traitOverridesPreserveInheritedContextAtLeaf() throws {
        try show(BRootViewController {
            BTraitOverridesViewController(set: \.accessibility, to: BAccessibility(isVoiceOverRunning: true)) {
                UIViewController()
            }
        }) { root in
            root.view.layoutIfNeeded()
            guard
                let overridesVC = root.children.first as? BTraitOverridesViewController<UIViewController>,
                let leaf = overridesVC.content,
                let rootContext = root.context
            else {
                Issue.record("Expected override container, leaf, and root context")
                return
            }

            let leafContext = leaf.traitCollection.bContext
            #expect(leafContext.baseTraits == rootContext.baseTraits)
            #expect(leafContext.themes == rootContext.themes)
            #expect(leafContext.traits.accessibility == BAccessibility(isVoiceOverRunning: true))
        }
    }

    @Test("Trait override container publishes full inherited context to traitOverrides")
    func traitOverridesPublishedContextPreservesBaseAndThemes() throws {
        try show(BRootViewController {
            BTraitOverridesViewController(set: \.accessibility, to: BAccessibility(isVoiceOverRunning: true)) {
                UIViewController()
            }
        }) { root in
            root.view.layoutIfNeeded()
            guard
                let overridesVC = root.children.first as? BTraitOverridesViewController<UIViewController>,
                let rootContext = root.context
            else {
                Issue.record("Expected override container and root context")
                return
            }

            let published = overridesVC.traitOverrides.bContext
            #expect(published.baseTraits == rootContext.baseTraits)
            #expect(published.themes == rootContext.themes)
            #expect(published.traits.accessibility == BAccessibility(isVoiceOverRunning: true))
        }
    }
}
