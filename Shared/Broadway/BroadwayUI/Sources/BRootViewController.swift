//
//  BRootViewController.swift
//  BroadwayUI
//

import BroadwayCore
import SwiftUI
import UIKit

/// A container view controller that owns the root ``BContext`` and
/// propagates it to all descendants via a custom `UITraitCollection` trait.
///
/// `BRootViewController` manages a ``BTraitsObserver``, keeping
/// ``BContext/traits`` in sync with system changes and re-publishing
/// the updated context through `traitOverrides`.
///
/// Child view controller creation, trait observation, and context setup
/// are deferred until the view controller enters a valid view hierarchy
/// (view loaded and in a window). This ensures traits can be read from
/// an actual hierarchy rather than from a detached controller.
///
/// Use the designated initializer to wrap an arbitrary child view controller,
/// or the convenience initializer to embed SwiftUI content directly.
///
/// ```swift
/// let root = BRootViewController {
///     ContentView()
/// }
/// window.rootViewController = root
/// ```
public final class BRootViewController: UIViewController {
    // MARK: Public

    /// The current context, available after the view controller has been
    /// added to a valid view hierarchy. `nil` before setup completes.
    public private(set) var context: BContext? {
        didSet {
            if let context {
                traitOverrides.bContext = context
            }
        }
    }

    // MARK: Initialization

    /// Creates a root container whose child view controller is produced
    /// lazily by the given closure once the container enters a valid
    /// view hierarchy.
    public init(child: @escaping () -> UIViewController) {
        makeChild = child

        super.init(nibName: nil, bundle: nil)
    }

    /// Creates a root container that hosts SwiftUI content.
    public convenience init(
        @ViewBuilder content: () -> some View,
    ) {
        let rootView = content()
        self.init { UIHostingController(rootView: rootView) }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: Lifecycle

    override public func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        setUpIfNeeded()
    }

    override public func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        child?.view.frame = view.bounds
    }

    // MARK: Private

    private let makeChild: () -> UIViewController

    private var child: UIViewController?
    private var traitsObserver: BTraitsObserver?

    private func setUpIfNeeded() {
        guard child == nil else { return }

        // TODO: Walk up the tree and don't make an observer if we're nested in another root
        // further up the tree.

        let observer = BTraitsObserver(traits: .system, from: self) { [weak self] traits in
            self?.context?.baseTraits = traits
        }

        traitsObserver = observer

        context = BContext(traits: observer.traits)

        observer.start()

        let child = makeChild()
        self.child = child

        addChild(child)
        child.didMove(toParent: self)

        child.view.frame = view.bounds
        view.addSubview(child.view)
    }
}
