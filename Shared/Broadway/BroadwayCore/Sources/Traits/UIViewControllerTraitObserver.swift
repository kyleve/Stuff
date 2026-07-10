//
//  UIViewControllerTraitObserver.swift
//  BroadwayCore
//

import UIKit

/// A reusable ``BTraitsValueObserver`` that monitors UIKit trait changes
/// on a specific view controller via `registerForTraitChanges`.
///
/// Use this for ``BTraitsValue`` types whose values are derived from
/// `UITraitCollection` properties (e.g. user interface style,
/// preferred content size category).
@MainActor
public final class UIViewControllerTraitObserver: BTraitsValueObserver {
    private weak var viewController: UIViewController?
    private let uiTraits: [any UITraitDefinition.Type]
    private let onChange: @MainActor @Sendable (UIViewController) -> Void
    private var registration: (any UITraitChangeRegistration)?

    public init(
        observing uiTraits: [any UITraitDefinition.Type],
        on viewController: UIViewController,
        onChange: @MainActor @escaping @Sendable (UIViewController) -> Void,
    ) {
        self.viewController = viewController
        self.uiTraits = uiTraits
        self.onChange = onChange
    }

    public func start() {
        guard registration == nil, let viewController else { return }

        registration = viewController.registerForTraitChanges(uiTraits) { [weak self] (vc: UIViewController, _: UITraitCollection) in
            self?.onChange(vc)
        }
    }

    public func stop() {
        guard let registration, let viewController else { return }

        viewController.unregisterForTraitChanges(registration)
        self.registration = nil
    }
}
