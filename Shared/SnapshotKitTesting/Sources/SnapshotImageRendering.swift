import SnapshotTesting
import TestHostSupport
import UIKit

/// Default fraction of pixels that must match within the perceptual tolerance.
public let defaultSnapshotPrecision: Float = 0.999

/// Default perceptual tolerance. ~98% mimics the human eye and absorbs
/// sub-visible antialiasing / subpixel noise without hiding real regressions.
public let defaultSnapshotPerceptualPrecision: Float = 0.98

/// Renders a view controller to an image at its own size on the fixed CI
/// simulator.
///
/// Overrides safe-area insets (default `.zero`) so the image is independent of the
/// host device, disables animations and drains any in-flight animation, hides
/// text-input cursors, and — for accessibility captures — wraps the content so the
/// image is VoiceOver-annotated. The capture is taken through a tile-and-stitch
/// wrapper so views taller/wider than ~2000pt (which UIKit otherwise renders
/// blank) come out whole.
///
/// Requires the StuffTestHost key window; call only from a hosted test bundle.
@MainActor
public func renderSnapshotImage(
    of viewController: UIViewController,
    safeAreaInsets: UIEdgeInsets? = .zero,
    isAccessibility: Bool = false,
    onAddedToWindow: @MainActor () -> Void = {},
) -> UIImage {
    func capture() -> UIImage {
        guard let window = hostKeyWindow() else {
            preconditionFailure(
                "SnapshotKitTesting requires the StuffTestHost key window. Run snapshot tests in a hosted bundle.",
            )
        }

        let originalRoot = window.rootViewController
        let originalFrame = window.frame
        let initialContentFrame = viewController.view.frame
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer {
            CATransaction.performWithoutAnimation { window.rootViewController = originalRoot }
            window.frame = originalFrame
            viewController.view.frame = initialContentFrame
            UIView.setAnimationsEnabled(animationsWereEnabled)
        }

        let captureViewController: UIViewController = isAccessibility
            ? AccessibilitySnapshotViewController(wrapping: viewController)
            : viewController
        let wrappingViewController = SnapshotWrappingViewController(captureViewController)

        window.frame.size = viewController.view.frame.size
        CATransaction.performWithoutAnimation { window.rootViewController = wrappingViewController }

        if let accessibilityViewController =
            captureViewController as? AccessibilitySnapshotViewController
        {
            accessibilityViewController.parseAccessibility()
        }

        wrappingViewController.view.setNeedsLayout()
        CATransaction.performWithoutAnimation(wrappingViewController.view.layoutIfNeeded)

        viewController.view.hideTextInputCursors()
        drainInFlightAnimations()

        onAddedToWindow()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))

        return tileAndStitchImage(of: wrappingViewController)
    }

    if let safeAreaInsets {
        return swizzle(safeAreaInsets: safeAreaInsets, for: viewController, operation: capture)
    }
    return capture()
}

extension Snapshotting where Value == UIViewController, Format == UIImage {
    /// A snapshot strategy that renders a view controller through the SnapshotKit
    /// pipeline (safe-area override, animation quiescing, cursor hiding, and — when
    /// `isAccessibility` is set — VoiceOver annotation) at its own size on the
    /// fixed CI simulator.
    public static func snapshotKitImage(
        precision: Float = defaultSnapshotPrecision,
        perceptualPrecision: Float = defaultSnapshotPerceptualPrecision,
        isAccessibility: Bool = false,
        onAddedToWindow: @escaping @MainActor () -> Void = {},
    ) -> Self {
        SimplySnapshotting
            .image(precision: precision, perceptualPrecision: perceptualPrecision, scale: nil)
            .pullback { viewController in
                MainActor.assumeIsolated {
                    renderSnapshotImage(
                        of: viewController,
                        isAccessibility: isAccessibility,
                        onAddedToWindow: onAddedToWindow,
                    )
                }
            }
    }
}
