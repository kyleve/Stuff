import SnapshotKit
import SnapshotTesting
import TestHostSupport
import UIKit

/// Default fraction of pixels that must match within the perceptual tolerance.
public let defaultSnapshotPrecision: Float = 0.999

/// Default perceptual tolerance. ~98% mimics the human eye and absorbs
/// sub-visible antialiasing / subpixel noise without hiding real regressions.
public let defaultSnapshotPerceptualPrecision: Float = 0.98

/// How a snapshot resolves the size it renders at.
public enum SnapshotSizing: Sendable {
    /// Use the view controller's current frame (a fixed device viewport).
    case fixed
    /// Size to fit the content at a fixed width, measured *after* the content is
    /// in the window and settled (so async `.task` loads are included, not a
    /// placeholder).
    case intrinsic(width: CGFloat)
}

/// Renders a view controller to an image on the fixed CI simulator.
///
/// Overrides safe-area insets (default `.zero`) so the image is independent of the
/// host device, disables animations and drains any in-flight animation, lets
/// async content settle (`settle` picks the mode — `.immediate` content skips
/// the digest-render loop), hides text-input cursors, and — for accessibility
/// captures — wraps the content so the image is VoiceOver-annotated. The capture
/// is taken through a tile-and-stitch wrapper so views taller/wider than ~2000pt
/// (which UIKit otherwise renders blank) come out whole.
///
/// The captured controller gets `SnapshotCaptureTrait` overridden to `true`, so
/// hosted SwiftUI content reads `\.isCapturingSnapshot` as `true` (via the
/// trait-bridged key in `SnapshotKit`) and can render a deterministic end-state
/// of motion that would otherwise never settle.
///
/// `onReadyToSnapshot` (a case's pre-capture hook) runs once, after the content
/// has settled and before the accessibility parse / cursor hiding / capture —
/// the deterministic point to focus a field or trigger a presented state. Its
/// effects are settled again (with the same `settle` mode) so they're committed
/// in the image. For `.intrinsic` sizing the content is measured *before* the
/// hook runs, so a hook must not change the content's ideal size.
///
/// `async` is load-bearing, not a convenience: the settle phase must *suspend*
/// (freeing the main actor) for SwiftUI `.task`-driven content to load — see
/// ``settleContent(_:minDuration:maxDuration:)``. Callers assert on the returned
/// image (``assertSnapshots(of:named:configurations:record:fileID:file:testName:line:column:)``
/// does this) rather than through a synchronous `Snapshotting` pullback, which
/// could never settle such content.
///
/// Captures are serialized process-wide through ``SnapshotCaptureLock``: the
/// pipeline holds process-global state (the safe-area swizzle, the animations
/// flag, the one host window) across those suspensions, so a concurrent call
/// queues behind the in-flight capture instead of corrupting it. Re-entering
/// from within a capture (a hook rendering another snapshot) traps.
///
/// The returned image is round-tripped through PNG encoding before it's handed
/// to the comparison: the perceptual compare must see byte-identical input to
/// what's flushed to disk, or wide-gamut in-memory captures diff against sRGB
/// PNG references even when the on-disk artifacts are pixel-identical (the
/// in-memory-vs-on-disk deltaE flake).
///
/// Requires the StuffTestHost key window; call only from a hosted test bundle.
@MainActor
public func renderSnapshotImage(
    of viewController: UIViewController,
    sizing: SnapshotSizing = .fixed,
    safeAreaInsets: UIEdgeInsets? = .zero,
    isAccessibility: Bool = false,
    settle: SnapshotSettle = .settled,
    onReadyToSnapshot: (@MainActor () async -> Void)? = nil,
) async -> UIImage {
    await SnapshotCaptureLock.withLock {
        await renderSnapshotImageLocked(
            of: viewController,
            sizing: sizing,
            safeAreaInsets: safeAreaInsets,
            isAccessibility: isAccessibility,
            settle: settle,
            onReadyToSnapshot: onReadyToSnapshot,
        )
    }
}

/// The capture body of
/// ``renderSnapshotImage(of:sizing:safeAreaInsets:isAccessibility:settle:onReadyToSnapshot:)``,
/// run while holding ``SnapshotCaptureLock``.
@MainActor
private func renderSnapshotImageLocked(
    of viewController: UIViewController,
    sizing: SnapshotSizing,
    safeAreaInsets: UIEdgeInsets?,
    isAccessibility: Bool,
    settle: SnapshotSettle,
    onReadyToSnapshot: (@MainActor () async -> Void)?,
) async -> UIImage {
    func capture() async -> UIImage {
        // `hostKeyWindow()` is the specific window `StuffTestHost` stamps with
        // `isMainTestHostWindow` — the guaranteed root window we set up, not
        // merely whatever window happens to be key. So this is stable regardless
        // of any transient key-window changes during a capture.
        guard let window = hostKeyWindow(), let hostRoot = window.rootViewController else {
            preconditionFailure(
                "SnapshotKitTesting requires the StuffTestHost key window. Run snapshot tests in a hosted bundle.",
            )
        }

        let initialContentFrame = viewController.view.frame
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer {
            viewController.view.frame = initialContentFrame
            viewController.traitOverrides.remove(SnapshotCaptureTrait.self)
            UIView.setAnimationsEnabled(animationsWereEnabled)
        }

        // Set on the content controller itself (not a wrapper) so it survives
        // re-hosting between the intrinsic-measurement probe and the capture
        // wrapper; UIKit propagates it down the tree and the bridged key
        // surfaces it to SwiftUI as `\.isCapturingSnapshot`.
        viewController.traitOverrides[SnapshotCaptureTrait.self] = true

        await resolveContentSize(
            of: viewController,
            sizing: sizing,
            settle: settle,
            hostedIn: hostRoot,
            window: window,
        )

        let captureViewController: UIViewController = isAccessibility
            ? AccessibilitySnapshotViewController(wrapping: viewController)
            : viewController
        let wrappingViewController = SnapshotWrappingViewController(captureViewController)

        // Host inside the already-appeared StuffTestHost root VC. Adding a child VC
        // (and its view) to an on-screen, appeared parent drives the real UIKit
        // appearance lifecycle (verified: `viewWillAppear`/`viewDidAppear`/SwiftUI
        // `onAppear` all fire through the containment forwarding — no manual
        // `beginAppearanceTransition` needed).
        hostChildForCapture(wrappingViewController, in: hostRoot)
        defer { removeChildAfterCapture(wrappingViewController) }

        wrappingViewController.view.setNeedsLayout()
        CATransaction.performWithoutAnimation(wrappingViewController.view.layoutIfNeeded)
        await settleForCapture(wrappingViewController.view, settle: settle)

        // The pre-capture hook sees fully settled content, then its own
        // effects (a focused field, a presented state) are settled before the
        // accessibility parse and capture below reflect them.
        if let onReadyToSnapshot {
            await onReadyToSnapshot()
            wrappingViewController.view.setNeedsLayout()
            CATransaction.performWithoutAnimation(wrappingViewController.view.layoutIfNeeded)
            await settleForCapture(wrappingViewController.view, settle: settle)
        }

        // Parse accessibility only after the content has settled, so the
        // annotation reflects the loaded/revealed state (not a placeholder), then
        // re-lay-out at the size `parseAccessibility` sizes the wrapper to.
        if let accessibilityViewController =
            captureViewController as? AccessibilitySnapshotViewController
        {
            accessibilityViewController.parseAccessibility()
            wrappingViewController.view.frame.size = accessibilityViewController.view.frame.size
            wrappingViewController.view.setNeedsLayout()
            CATransaction.performWithoutAnimation(wrappingViewController.view.layoutIfNeeded)
        }

        viewController.view.hideTextInputCursors()
        drainInFlightAnimations()

        let image = tileAndStitchImage(of: wrappingViewController)
        // Round-trip through PNG bytes (preserving scale, which `UIImage(data:)`
        // alone would reset to 1) so the compare and the disk artifact are the
        // same bytes — see the doc comment above.
        guard let pngData = image.pngData(),
              let decoded = UIImage(data: pngData, scale: image.scale)
        else {
            preconditionFailure("Snapshot capture could not be PNG-encoded.")
        }
        return decoded
    }

    if let safeAreaInsets {
        return await swizzle(
            safeAreaInsets: safeAreaInsets,
            for: viewController,
            operation: capture,
        )
    }
    return await capture()
}

/// Adds `child` (sized to its view's current frame) into the appeared host root
/// via the full `addChild` → attach-view → `didMove` contract, so the child — and
/// the SwiftUI content it hosts — runs its real appearance lifecycle.
@MainActor
private func hostChildForCapture(_ child: UIViewController, in hostRoot: UIViewController) {
    hostRoot.addChild(child)
    child.view.frame = CGRect(origin: .zero, size: child.view.frame.size)
    hostRoot.view.addSubview(child.view)
    child.didMove(toParent: hostRoot)
}

/// Tears down a controller hosted by ``hostChildForCapture(_:in:)``.
@MainActor
private func removeChildAfterCapture(_ child: UIViewController) {
    child.willMove(toParent: nil)
    child.view.removeFromSuperview()
    child.removeFromParent()
}

/// For `.intrinsic` sizing, hosts the content at the target width with the full
/// appearance lifecycle driven (so SwiftUI `.task` loads and finite time-based
/// reveals run), lets it settle, then measures `sizeThatFits` and pins the frame —
/// so a content-loading component is sized to its loaded content rather than an
/// empty placeholder. `.fixed` sizing leaves the frame untouched.
///
/// The measurement iterates to a fixed point: a lazy container (`LazyVStack` in
/// a `ScrollView`) reports an *estimated* content height until its rows
/// materialize, and rows only materialize once the viewport reaches them — a
/// single measurement of a full-content scroll capture would cut the year off
/// mid-October. Growing the frame to each estimate and re-laying-out
/// materializes more rows and refines the next measurement; non-lazy content is
/// stable on the first pass, so it measures exactly as before.
///
/// The content is hosted through a throwaway wrapper added as a child of the
/// appeared host root (not a bare subview): only a real appearance transition
/// starts the content's `.task`/`onAppear`. The wrapper is torn down and the
/// content detached before returning, so the caller can re-parent the same view
/// controller into the capture wrapper.
@MainActor
private func resolveContentSize(
    of viewController: UIViewController,
    sizing: SnapshotSizing,
    settle: SnapshotSettle,
    hostedIn hostRoot: UIViewController,
    window: UIWindow,
) async {
    guard case let .intrinsic(width) = sizing else { return }

    let probeHeight = max(window.bounds.height, 1)
    viewController.view.frame = CGRect(x: 0, y: 0, width: width, height: probeHeight)

    let probeWrapper = SnapshotWrappingViewController(viewController)
    hostChildForCapture(probeWrapper, in: hostRoot)
    probeWrapper.view.setNeedsLayout()
    CATransaction.performWithoutAnimation(probeWrapper.view.layoutIfNeeded)
    await settleForCapture(probeWrapper.view, settle: settle)

    func measureContent() -> CGSize {
        var measured = viewController.view
            .sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        measured.width = width
        if !measured.height.isFinite || measured.height <= 0 {
            measured.height = 1
        }
        return measured
    }

    var measured = measureContent()
    for _ in 0 ..< 10 {
        viewController.view.frame = CGRect(origin: .zero, size: measured)
        probeWrapper.view.frame.size = measured
        CATransaction.performWithoutAnimation(probeWrapper.view.layoutIfNeeded)
        let remeasured = measureContent()
        if abs(remeasured.height - measured.height) < 0.5 { break }
        measured = remeasured
    }

    // Detach the content VC from the probe wrapper first (so the caller can
    // re-wrap it), then tear the probe wrapper down.
    viewController.willMove(toParent: nil)
    viewController.removeFromParent()
    removeChildAfterCapture(probeWrapper)

    viewController.view.frame = CGRect(origin: .zero, size: measured)
    CATransaction.performWithoutAnimation(viewController.view.layoutIfNeeded)
}
