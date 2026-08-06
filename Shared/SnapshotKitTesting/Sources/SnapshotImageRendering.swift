import SnapshotKit
import SnapshotTesting
import TestHostSupport
import UIKit

/// Default fraction of pixels that must match within the perceptual tolerance.
public let defaultSnapshotPrecision: Float = 0.999

/// Default perceptual tolerance, as a ΔE threshold of `(1 - value) * 100` — so
/// a pixel may differ by up to ΔE 10 before it counts against
/// ``defaultSnapshotPrecision``.
///
/// Loose on purpose, because `CILabDeltaE` — the metric behind the verdict — is
/// far steeper near black than the CIE76 it approximates. A ±1/255 difference,
/// which is what a different GPU or OS build produces and is invisible by
/// construction, measures ΔE 0.15-0.19 in pastels but up to 12 in near-black
/// pixels. This knob bounds a pixel's *amplitude*; how much of the image may
/// exceed it is ``defaultSnapshotPrecision``'s job. The measurements, and why
/// 10 rather than 5, are in `AGENTS.md`.
public let defaultSnapshotPerceptualPrecision: Float = 0.90

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
/// ``settleContent(_:named:minDuration:maxDuration:timing:)``. Callers assert on the returned
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
///
/// `named` labels the capture in settle-phase failures — `assertSnapshots`
/// passes the full snapshot identifier, so a timeout on one configuration of a
/// 16-image matrix names which one (the gap that made CI's About-screen settle
/// failures undiagnosable from the result bundle alone).
@MainActor
public func renderSnapshotImage(
    of viewController: UIViewController,
    named name: String,
    sizing: SnapshotSizing = .fixed,
    safeAreaInsets: UIEdgeInsets? = .zero,
    isAccessibility: Bool = false,
    settle: SnapshotSettle = .settled,
    onReadyToSnapshot: (@MainActor () async -> Void)? = nil,
) async -> UIImage {
    await renderSnapshotCapture(
        of: viewController,
        named: name,
        sizing: sizing,
        safeAreaInsets: safeAreaInsets,
        isAccessibility: isAccessibility,
        settle: settle,
        onReadyToSnapshot: onReadyToSnapshot,
        timing: SnapshotCaptureTiming(identifier: name, isEnabled: false),
    ).image
}

/// A finished capture: the image to compare, and the PNG bytes it was
/// round-tripped through.
///
/// Both, because they answer different questions and re-deriving either costs a
/// full encode or decode: `assertSnapshot` wants the image, while the reference
/// byte-comparison (``compareAgainstReference(capturedPNG:referenceURL:)``) wants
/// exactly the bytes that would be written to disk.
@_spi(Testing) public struct SnapshotCapture {
    public let image: UIImage
    public let pngData: Data
}

/// ``renderSnapshotImage(of:named:sizing:safeAreaInsets:isAccessibility:settle:onReadyToSnapshot:)``
/// with a caller-supplied phase recorder, so `assertSnapshots` can attribute the
/// capture *and* the comparison that follows it to one line of output, and can
/// compare the captured bytes against the reference without re-encoding.
@MainActor
@_spi(Testing) public func renderSnapshotCapture(
    of viewController: UIViewController,
    named name: String,
    sizing: SnapshotSizing,
    safeAreaInsets: UIEdgeInsets?,
    isAccessibility: Bool,
    settle: SnapshotSettle,
    onReadyToSnapshot: (@MainActor () async -> Void)?,
    timing: SnapshotCaptureTiming,
) async -> SnapshotCapture {
    await SnapshotCaptureLock.withLock {
        await renderSnapshotImageLocked(
            of: viewController,
            named: name,
            sizing: sizing,
            safeAreaInsets: safeAreaInsets,
            isAccessibility: isAccessibility,
            settle: settle,
            onReadyToSnapshot: onReadyToSnapshot,
            timing: timing,
        )
    }
}

/// The capture body of
/// ``renderSnapshotImage(of:named:sizing:safeAreaInsets:isAccessibility:settle:onReadyToSnapshot:)``,
/// run while holding ``SnapshotCaptureLock``.
@MainActor
private func renderSnapshotImageLocked(
    of viewController: UIViewController,
    named name: String,
    sizing: SnapshotSizing,
    safeAreaInsets: UIEdgeInsets?,
    isAccessibility: Bool,
    settle: SnapshotSettle,
    onReadyToSnapshot: (@MainActor () async -> Void)?,
    timing: SnapshotCaptureTiming,
) async -> SnapshotCapture {
    func capture() async -> SnapshotCapture {
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

        await timing.measure(.intrinsicMeasure) {
            await resolveContentSize(
                of: viewController,
                named: name,
                sizing: sizing,
                settle: settle,
                hostedIn: hostRoot,
                window: window,
                timing: timing,
            )
        }

        let captureViewController: UIViewController = isAccessibility
            ? AccessibilitySnapshotViewController(
                wrapping: viewController,
                ownsContent: viewController.view.bounds.height <= window.bounds.height,
            )
            : viewController
        let wrappingViewController = SnapshotWrappingViewController(captureViewController)

        // Host inside the already-appeared StuffTestHost root VC. Adding a child VC
        // (and its view) to an on-screen, appeared parent drives the real UIKit
        // appearance lifecycle (verified: `viewWillAppear`/`viewDidAppear`/SwiftUI
        // `onAppear` all fire through the containment forwarding — no manual
        // `beginAppearanceTransition` needed).
        timing.measure(.host) {
            hostChildForCapture(wrappingViewController, in: hostRoot)
            wrappingViewController.view.setNeedsLayout()
            CATransaction.performWithoutAnimation(wrappingViewController.view.layoutIfNeeded)
        }
        defer { removeChildAfterCapture(wrappingViewController) }

        await reportIfUnsettled(
            timing.measure(.settle) {
                await settleForCapture(
                    wrappingViewController.view,
                    named: name,
                    settle: settle,
                    timing: timing,
                )
            },
            phase: "content",
            of: viewController,
            named: name,
        )

        // The pre-capture hook sees fully settled content, then its own
        // effects (a focused field, a presented state) are settled before the
        // accessibility parse and capture below reflect them.
        if let onReadyToSnapshot {
            await reportIfUnsettled(
                timing.measure(.hook) {
                    await onReadyToSnapshot()
                    wrappingViewController.view.setNeedsLayout()
                    CATransaction
                        .performWithoutAnimation(wrappingViewController.view.layoutIfNeeded)
                    return await settleForCapture(
                        wrappingViewController.view,
                        named: name,
                        settle: settle,
                        timing: timing,
                    )
                },
                phase: "onReadyToSnapshot",
                of: viewController,
                named: name,
            )
        }

        // Parse accessibility only after the content has settled, so the
        // annotation reflects the loaded/revealed state (not a placeholder), then
        // re-lay-out at the size `parseAccessibility` sizes the wrapper to.
        if let accessibilityViewController =
            captureViewController as? AccessibilitySnapshotViewController
        {
            timing.measure(.accessibilityParse) {
                accessibilityViewController.parseAccessibility()
                wrappingViewController.view.frame.size = accessibilityViewController.view.frame.size
                wrappingViewController.view.setNeedsLayout()
                CATransaction.performWithoutAnimation(wrappingViewController.view.layoutIfNeeded)
            }
        }

        viewController.view.hideTextInputCursors()
        timing.measure(.drain) { drainInFlightAnimations() }

        let image = timing.measure(.tileStitch) {
            tileAndStitchImage(of: wrappingViewController, timing: timing)
        }
        // Round-trip through PNG bytes (preserving scale, which `UIImage(data:)`
        // alone would reset to 1) so the compare and the disk artifact are the
        // same bytes — see the doc comment above.
        return timing.measure(.pngRoundTrip) {
            guard let pngData = image.pngData(),
                  let decoded = UIImage(data: pngData, scale: image.scale)
            else {
                preconditionFailure("Snapshot capture could not be PNG-encoded.")
            }
            return SnapshotCapture(image: decoded, pngData: pngData)
        }
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
/// empty placeholder. UIKit-backed SwiftUI containers such as `Form` report
/// their viewport rather than their ideal height, so a root-filling scroll view's
/// content size is used when it is taller. `.fixed` sizing leaves the frame
/// untouched.
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
    named name: String,
    sizing: SnapshotSizing,
    settle: SnapshotSettle,
    hostedIn hostRoot: UIViewController,
    window: UIWindow,
    timing: SnapshotCaptureTiming,
) async {
    guard case let .intrinsic(width) = sizing else { return }

    let probeHeight = max(window.bounds.height, 1)
    viewController.view.frame = CGRect(x: 0, y: 0, width: width, height: probeHeight)

    let probeWrapper = SnapshotWrappingViewController(viewController)
    hostChildForCapture(probeWrapper, in: hostRoot)
    probeWrapper.view.setNeedsLayout()
    CATransaction.performWithoutAnimation(probeWrapper.view.layoutIfNeeded)
    await reportIfUnsettled(
        settleForCapture(probeWrapper.view, named: name, settle: settle, timing: timing),
        phase: "intrinsic measurement",
        of: viewController,
        named: name,
    )

    func measureContent() -> CGSize {
        var measured = viewController.view
            .sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        measured.width = width
        if !measured.height.isFinite || measured.height <= 0 {
            measured.height = 1
        }
        if let scrollContentHeight = viewController.view.rootScrollContentHeight,
           scrollContentHeight > measured.height
        {
            measured.height = scrollContentHeight
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

extension UIView {
    /// The content height of a scroll view that fills this view, if one exists.
    ///
    /// `Form` and `List` are backed by UIKit scroll views whose hosting view
    /// answers `sizeThatFits` with only the current viewport. Restricting the
    /// fallback to a root-filling scroll view avoids expanding an intentionally
    /// fixed-height nested scroller inside an otherwise intrinsic component.
    fileprivate var rootScrollContentHeight: CGFloat? {
        descendants
            .compactMap { view -> CGFloat? in
                guard let scrollView = view as? UIScrollView else { return nil }
                let visibleFrame = scrollView.convert(scrollView.bounds, to: self)
                guard visibleFrame.width >= bounds.width - 1,
                      visibleFrame.height >= bounds.height - 1,
                      scrollView.contentSize.height.isFinite,
                      scrollView.contentSize.height > 0
                else { return nil }
                return scrollView.contentSize.height
            }
            .max()
    }

    private var descendants: [UIView] {
        subviews + subviews.flatMap(\.descendants)
    }
}
