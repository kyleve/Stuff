//
//  BTraitOverridesViewController.swift
//  BroadwayUI
//

import BroadwayCore
import UIKit

/// A container view controller that applies ``BTraits/Overrides`` to the
/// inherited ``BContext`` before passing it to its child.
///
/// Override values are refreshed when embedded (`didMove(toParent:)`) and when
/// inherited traits change, so the subtree keeps the correct merged context
/// before the child is created.
///
/// Child creation is deferred until the view controller enters a valid view
/// hierarchy (`viewIsAppearing`), matching ``BRootViewController``'s lazy setup pattern.
public final class BTraitOverridesViewController<Content: UIViewController>: UIViewController {
    // MARK: Public

    /// The child view controller, available after setup completes.
    public private(set) var content: Content?

    public struct Context {
        public let traits: BTraits
    }

    // MARK: Initialization

    public init(
        _ content: @escaping () -> Content,
        overrides: @escaping (Context, inout BTraits.Overrides) -> Void,
    ) {
        makeContent = content
        self.overrides = overrides

        super.init(nibName: nil, bundle: nil)

        registerForTraitChanges(
            [BContextTrait.self],
            action: #selector(onTraitsDidChange(vc:previous:)),
        )
    }

    public convenience init<Value>(
        set keyPath: WritableKeyPath<BTraits.Overrides, Value>,
        to value: Value,
        content: @escaping () -> Content,
    ) {
        self.init(content) { _, overrides in
            overrides[keyPath: keyPath] = value
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: Lifecycle

    override public func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)

        if parent != nil {
            applyOverrides()
        }
    }

    override public func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        setUpIfNeeded()
    }

    override public func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        content?.view.frame = view.bounds
    }

    // MARK: Private

    private let makeContent: () -> Content
    private let overrides: (Context, inout BTraits.Overrides) -> Void

    private func setUpIfNeeded() {
        guard content == nil else { return }

        applyOverrides()

        let child = makeContent()
        content = child

        addChild(child)
        child.didMove(toParent: self)

        child.view.frame = view.bounds
        view.addSubview(child.view)
    }

    private func applyOverrides() {
        // Prefer the parent's resolved traits: `traitCollection` on `self` can lag
        // behind the ancestor chain for custom `UITraitDefinition`s during
        // `viewIsAppearing`, so read the merged collection from `parent` when embedded.
        var context = parent?.traitCollection.bContext ?? traitCollection.bContext
        var current = context.traitOverrides
        overrides(.init(traits: context.traits), &current)
        context.traitOverrides = current
        traitOverrides.bContext = context
    }

    @objc private func onTraitsDidChange(
        vc _: UIViewController,
        previous _: UITraitCollection,
    ) {
        applyOverrides()
    }
}
