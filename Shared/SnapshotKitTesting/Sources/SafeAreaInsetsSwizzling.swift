import UIKit

/// Swizzles `UIView.safeAreaInsets` for the duration of `operation` so a captured
/// view controller sees `safeAreaInsets` (default `.zero`) instead of the host
/// simulator's device insets. This decouples the image from the physical
/// simulator (notch / home indicator) and still honors each view controller's
/// `additionalSafeAreaInsets`. Unswizzled in all paths.
@MainActor
func swizzle<Output>(
    safeAreaInsets: UIEdgeInsets,
    for viewController: UIViewController,
    operation: () -> Output,
) -> Output {
    _overrideSafeAreaInsets = safeAreaInsets
    _overrideViewController = viewController
    UIView.swizzleSafeAreaInsets()
    defer {
        _overrideSafeAreaInsets = .zero
        _overrideViewController = nil
        UIView.unswizzleSafeAreaInsets()
    }
    return operation()
}

@MainActor private var _overrideViewController: UIViewController?
@MainActor private var _overrideSafeAreaInsets: UIEdgeInsets = .zero

extension UIView {
    fileprivate static func swizzleSafeAreaInsets() {
        exchangeSafeAreaImplementations()
    }

    fileprivate static func unswizzleSafeAreaInsets() {
        exchangeSafeAreaImplementations()
    }

    fileprivate static func exchangeSafeAreaImplementations() {
        guard
            let original = class_getInstanceMethod(self, #selector(getter: UIView.safeAreaInsets)),
            let swizzled = class_getInstanceMethod(
                self,
                #selector(getter: UIView.snapshotKitOverriddenSafeAreaInsets),
            )
        else {
            assertionFailure("UIView.safeAreaInsets getter could not be swizzled for snapshotting.")
            return
        }
        method_exchangeImplementations(original, swizzled)
    }

    @objc private var snapshotKitOverriddenSafeAreaInsets: UIEdgeInsets {
        guard let tested = _overrideViewController else {
            return _overrideSafeAreaInsets
        }

        // The direct container of the tested view reports the raw override.
        if subviews.contains(tested.view) {
            return _overrideSafeAreaInsets
        }

        // A view outside any view-controller hierarchy just gets the override.
        guard let owningViewController = snapshotKitOwningViewController else {
            return _overrideSafeAreaInsets
        }

        var sourceView = owningViewController.view!
        let isViewControllersView = sourceView === self

        // For a view controller's own view, derive insets from its superview so
        // additionalSafeAreaInsets can be layered on; otherwise use the owning
        // view controller's view as the conversion source.
        if isViewControllersView {
            guard let superview else { return _overrideSafeAreaInsets }
            sourceView = superview
        }

        let sourceSafeArea = sourceView.bounds.inset(by: sourceView.safeAreaInsets)
        let safeArea = sourceView.convert(sourceSafeArea, to: self)

        var insets = UIEdgeInsets(
            top: max(0, safeArea.minY),
            left: max(0, safeArea.minX),
            bottom: max(0, bounds.maxY - safeArea.maxY),
            right: max(0, bounds.maxX - safeArea.maxX),
        )

        if isViewControllersView {
            insets = insets + owningViewController.additionalSafeAreaInsets
        }

        return insets
    }

    private var snapshotKitOwningViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}

extension UIEdgeInsets {
    fileprivate static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            top: lhs.top + rhs.top,
            left: lhs.left + rhs.left,
            bottom: lhs.bottom + rhs.bottom,
            right: lhs.right + rhs.right,
        )
    }
}
