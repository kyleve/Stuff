import UIKit

/// Swizzles `UIView.safeAreaInsets` for the duration of `operation` so the
/// captured view controller's **root** sees `safeAreaInsets` (default `.zero`)
/// instead of the host simulator's device insets. This decouples the image from
/// the physical simulator (notch / home indicator). Unswizzled in all paths.
///
/// Only the captured root and its ancestors (the capture scaffolding up to the
/// window) report the override; views *inside* the hosted tree keep the native
/// implementation. UIKit composes safe areas root-down, so the interior sees the
/// zeroed device insets from our root **plus** everything legitimately layered on
/// mid-tree — navigation-bar overlap, `safeAreaInset` accessories, a VC's
/// `additionalSafeAreaInsets`. Two earlier designs failed here:
///
/// - Returning the override for **every** in-tree view erased those interior
///   contributions, so scroll content laid out flush under floating bars (a
///   summary screen crammed its text into the bar blur).
/// - Geometrically re-deriving the root's safe rect per view produced phantom
///   insets for translated content — a scroll container at offset y reported a
///   y-point top inset and the visible region laid out empty (blank CalendarView).
@MainActor
func swizzle<Output>(
    safeAreaInsets: UIEdgeInsets,
    for viewController: UIViewController,
    operation: () async -> Output,
) async -> Output {
    _overrideSafeAreaInsets = safeAreaInsets
    _overrideViewController = viewController
    UIView.swizzleSafeAreaInsets()
    defer {
        _overrideSafeAreaInsets = .zero
        _overrideViewController = nil
        UIView.unswizzleSafeAreaInsets()
    }
    return await operation()
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
        guard let tested = _overrideViewController, let testedView = tested.view else {
            return _overrideSafeAreaInsets
        }

        // The captured root and the scaffolding above it report the override;
        // everything inside the tree keeps the native implementation (which,
        // after the method exchange, *is* `snapshotKitOverriddenSafeAreaInsets`)
        // so interior contributions — bars, `safeAreaInset` accessories,
        // `additionalSafeAreaInsets` — still compose on top of the zeroed base.
        if self === testedView || testedView.isDescendant(of: self) {
            return _overrideSafeAreaInsets
        }
        return snapshotKitOverriddenSafeAreaInsets
    }
}
