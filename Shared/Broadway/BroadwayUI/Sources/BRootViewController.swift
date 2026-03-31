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
/// `BRootViewController` manages the ``BAccessibility/Observer``,
/// keeping ``BContext/traits`` in sync with system accessibility changes
/// and re-publishing the updated context through `traitOverrides`.
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

    /// The current context. Updated automatically when accessibility
    /// settings change. Read this to inspect the live state.
    public private(set) var context: BContext {
        didSet {
            traitOverrides.bContext = context
        }
    }

    // MARK: Initialization

    /// Creates a root container that embeds the given child view controller.
    public init(child: UIViewController) {
        context = BContext()
        self.child = child

        super.init(nibName: nil, bundle: nil)

        addChild(child)
        child.didMove(toParent: self)

        context.traits.accessibility = .current()
        traitOverrides.bContext = context

        accessibilityObserver = BAccessibility.observe { [weak self] _, new in
            guard let self else { return }
            context.traits.accessibility = new
        }
    }

    /// Creates a root container that hosts SwiftUI content.
    public convenience init(
        @ViewBuilder content: () -> some View,
    ) {
        self.init(child: UIHostingController(rootView: content()))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        child.view.frame = view.bounds
        view.addSubview(child.view)

        accessibilityObserver?.start()
    }

    override public func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        child.view.frame = view.bounds
    }

    // MARK: Private

    private let child: UIViewController

    private var accessibilityObserver: BAccessibility.Observer?
}
