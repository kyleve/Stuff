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
    /// placeholder), while retaining the requested minimum height.
    case intrinsic(width: CGFloat, minimumHeight: CGFloat)
    /// Start at a minimum viewport, then expand both dimensions to reveal the
    /// complete content of its primary viewport-filling scroll view.
    case fullContent2D(minimumSize: CGSize)
}

/// A capture failure that callers can report without comparing or recording an
/// invalid image.
public enum SnapshotRenderingError: Error, Equatable, Sendable {
    /// The CI-only settle multiplier was malformed or outside its supported
    /// safety range.
    case invalidSettleTimeoutMultiplier(value: String)
    /// A pre-measure hook was supplied for a fixed-size capture, where there is
    /// no intrinsic measurement host on which to run it.
    case measurementHookRequiresIntrinsicSizing(name: String)
    /// Deterministic content readiness did not arrive before the capture's
    /// effective settle ceiling.
    case measurementReadinessTimedOut(name: String, budget: TimeInterval)
    /// Full-content measurement did not reach a stable height within the
    /// bounded fixed-point pass budget.
    case intrinsicHeightDidNotConverge(name: String, measuredHeights: [CGFloat])
    /// Two-axis full-content measurement did not reach a stable size within
    /// the bounded fixed-point pass budget.
    case fullContentSizeDidNotConverge(name: String, measuredSizes: [CGSize])
    /// A two-axis capture would exceed the renderer's bounded allocation.
    case fullContentSizeExceedsLimit(
        name: String,
        pixelWidth: Int,
        pixelHeight: Int,
        maximumPixelDimension: Int,
        maximumPixelCount: Int,
    )
}

extension SnapshotRenderingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case let .invalidSettleTimeoutMultiplier(value):
                return "Invalid SNAPSHOT_SETTLE_TIMEOUT_MULTIPLIER \"\(value)\"; use a finite value from 1 through 4."
            case let .measurementHookRequiresIntrinsicSizing(name):
                return "Snapshot \(name) declares onReadyToMeasure, but fixed sizing has no measured-content phase."
            case let .measurementReadinessTimedOut(name, budget):
                return "Snapshot \(name) measurement readiness did not complete within \(budget.formatted())s."
            case let .intrinsicHeightDidNotConverge(name, measuredHeights):
                let heights = measuredHeights.map { String(format: "%.1f", $0) }
                    .joined(separator: ", ")
                return "Snapshot \(name) intrinsic height did not converge: \(heights)."
            case let .fullContentSizeDidNotConverge(name, measuredSizes):
                let sizes = measuredSizes
                    .map { "\($0.width.formatted())×\($0.height.formatted())" }
                    .joined(separator: ", ")
                return "Snapshot \(name) two-axis full-content size did not converge: \(sizes)."
            case let .fullContentSizeExceedsLimit(
            name,
            pixelWidth,
            pixelHeight,
            maximumPixelDimension,
            maximumPixelCount,
        ):
                return "Snapshot \(name) would render at \(pixelWidth)×\(pixelHeight) pixels; two-axis captures are limited to \(maximumPixelDimension) pixels per dimension and \(maximumPixelCount) pixels total."
        }
    }
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
/// in the image. For measured-content sizing the content is measured *before*
/// the hook runs, so a hook must not change the content's ideal size.
/// `measurementReadiness` controls only the settle before size resolution; it
/// never shortens the final capture settle.
/// `onReadyToMeasure` runs earlier, after a measurement probe is hosted and laid
/// out but before that settle and size resolution. It is for deterministic
/// readiness signals whose completion can change ideal height. The hook is
/// invalid for `.fixed` sizing, is bounded by the capture's effective settle
/// ceiling, and must cooperate with task cancellation.
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
    measurementReadiness: SnapshotMeasurementReadiness = .sameAsCapture,
    onReadyToMeasure: (@MainActor () async -> Void)? = nil,
    settle: SnapshotSettle = .settled,
    onReadyToSnapshot: (@MainActor () async -> Void)? = nil,
) async throws -> UIImage {
    let settleTimeoutPolicy = try SnapshotSettleTimeoutPolicy.fromEnvironment()
    return try await renderSnapshotCapture(
        of: viewController,
        named: name,
        sizing: sizing,
        safeAreaInsets: safeAreaInsets,
        isAccessibility: isAccessibility,
        measurementReadiness: measurementReadiness,
        onReadyToMeasure: onReadyToMeasure,
        settle: settle,
        onReadyToSnapshot: onReadyToSnapshot,
        settleTimeoutPolicy: settleTimeoutPolicy,
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

/// ``renderSnapshotImage(of:named:sizing:safeAreaInsets:isAccessibility:measurementReadiness:onReadyToMeasure:settle:onReadyToSnapshot:)``
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
    measurementReadiness: SnapshotMeasurementReadiness,
    onReadyToMeasure: (@MainActor () async -> Void)?,
    settle: SnapshotSettle,
    onReadyToSnapshot: (@MainActor () async -> Void)?,
    settleTimeoutPolicy: SnapshotSettleTimeoutPolicy,
    timing: SnapshotCaptureTiming,
) async throws -> SnapshotCapture {
    try await SnapshotCaptureLock.withLock {
        try await renderSnapshotImageLocked(
            of: viewController,
            named: name,
            sizing: sizing,
            safeAreaInsets: safeAreaInsets,
            isAccessibility: isAccessibility,
            measurementReadiness: measurementReadiness,
            onReadyToMeasure: onReadyToMeasure,
            settle: settle,
            onReadyToSnapshot: onReadyToSnapshot,
            settleTimeoutPolicy: settleTimeoutPolicy,
            timing: timing,
        )
    }
}

/// The capture body of
/// ``renderSnapshotImage(of:named:sizing:safeAreaInsets:isAccessibility:measurementReadiness:onReadyToMeasure:settle:onReadyToSnapshot:)``,
/// run while holding ``SnapshotCaptureLock``.
@MainActor
private func renderSnapshotImageLocked(
    of viewController: UIViewController,
    named name: String,
    sizing: SnapshotSizing,
    safeAreaInsets: UIEdgeInsets?,
    isAccessibility: Bool,
    measurementReadiness: SnapshotMeasurementReadiness,
    onReadyToMeasure: (@MainActor () async -> Void)?,
    settle: SnapshotSettle,
    onReadyToSnapshot: (@MainActor () async -> Void)?,
    settleTimeoutPolicy: SnapshotSettleTimeoutPolicy,
    timing: SnapshotCaptureTiming,
) async throws -> SnapshotCapture {
    func capture() async throws -> SnapshotCapture {
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

        try await resolveContentSize(
            of: viewController,
            named: name,
            sizing: sizing,
            settle: measurementReadiness.resolvedSettle(captureSettle: settle),
            onReadyToMeasure: onReadyToMeasure,
            measurementHookMaximumDuration: settleTimeoutPolicy.maximumDuration(for: settle),
            hostedIn: hostRoot,
            window: window,
            timing: timing,
            settleTimeoutPolicy: settleTimeoutPolicy,
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
                    timeoutPolicy: settleTimeoutPolicy,
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
                        timeoutPolicy: settleTimeoutPolicy,
                    )
                },
                phase: "onReadyToSnapshot",
                of: viewController,
                named: name,
            )
        }

        // Parse accessibility only after the content has settled, so the
        // annotation reflects the loaded/revealed state (not a placeholder).
        // A raised settle floor opts accessibility rendering into a preparation
        // pass. That first pass starts one-time native material work caused by
        // temporarily inserting the content into AccessibilitySnapshot's
        // renderer. The annotated output is static during this bounded wait; the
        // wait gives the content's persistent native state time to finish. The
        // ordinary settle policies stay single-pass because another insertion can
        // change scrolling content.
        if let accessibilityViewController =
            captureViewController as? AccessibilitySnapshotViewController
        {
            func parseAccessibility() {
                accessibilityViewController.parseAccessibility()
                wrappingViewController.view.frame.size = accessibilityViewController.view.frame.size
                wrappingViewController.view.setNeedsLayout()
                CATransaction.performWithoutAnimation(wrappingViewController.view.layoutIfNeeded)
            }

            if case .settledAtLeast = settle {
                timing.measure(.accessibilityParse) {
                    parseAccessibility()
                }
                await reportIfUnsettled(
                    timing.measure(.settle) {
                        await settleForCapture(
                            wrappingViewController.view,
                            named: name,
                            settle: settle,
                            timing: timing,
                            timeoutPolicy: settleTimeoutPolicy,
                        )
                    },
                    phase: "accessibility preparation",
                    of: viewController,
                    named: name,
                )
            }
            timing.measure(.accessibilityParse) {
                parseAccessibility()
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
        return try await swizzle(
            safeAreaInsets: safeAreaInsets,
            for: viewController,
            operation: capture,
        )
    }
    return try await capture()
}

extension SnapshotMeasurementReadiness {
    fileprivate func resolvedSettle(captureSettle: SnapshotSettle) -> SnapshotSettle {
        switch self {
            case .sameAsCapture:
                captureSettle
            case .immediate:
                .immediate
            case .settled:
                .settled
        }
    }
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

/// For measured-content sizing, hosts the content at the initial viewport with
/// the full appearance lifecycle driven (so SwiftUI `.task` loads and finite
/// time-based reveals run), lets it settle, then measures `sizeThatFits` and
/// pins the frame — so a content-loading component is sized to its loaded
/// content rather than an empty placeholder. The result never falls below the
/// requested minimum height. UIKit-backed SwiftUI containers such as `Form`
/// report their viewport rather than their ideal height, so a full-width scroll
/// descendant's content size is used when it is taller. `.fixed` sizing leaves
/// the frame untouched.
///
/// The measurement iterates to a fixed point: a lazy container (`LazyVStack` in
/// a `ScrollView`) reports an *estimated* content height until its rows
/// materialize, and rows only materialize once the viewport reaches them — a
/// single measurement of a full-content scroll capture would cut the year off
/// mid-October. Growing the frame to each estimate and re-laying-out
/// materializes more rows and refines the next measurement; non-lazy content is
/// stable on the first pass, so it measures exactly as before. Two-axis sizing
/// follows the same bounded process with one viewport-filling scroll descendant
/// supplying both dimensions, then validates the rendered pixel allocation.
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
    onReadyToMeasure: (@MainActor () async -> Void)?,
    measurementHookMaximumDuration: TimeInterval,
    hostedIn hostRoot: UIViewController,
    window: UIWindow,
    timing: SnapshotCaptureTiming,
    settleTimeoutPolicy: SnapshotSettleTimeoutPolicy,
) async throws {
    let probeSize: CGSize
    switch sizing {
        case .fixed:
            if onReadyToMeasure != nil {
                throw SnapshotRenderingError.measurementHookRequiresIntrinsicSizing(name: name)
            }
            return
        case let .intrinsic(width, _):
            probeSize = CGSize(width: width, height: max(window.bounds.height, 1))
        case let .fullContent2D(minimumSize):
            probeSize = CGSize(
                width: max(minimumSize.width, 1),
                height: max(minimumSize.height, 1),
            )
    }

    let probeWrapper = timing.measure(.intrinsicMeasure) {
        viewController.view.frame = CGRect(origin: .zero, size: probeSize)

        let wrapper = SnapshotWrappingViewController(viewController)
        hostChildForCapture(wrapper, in: hostRoot)
        wrapper.view.setNeedsLayout()
        CATransaction.performWithoutAnimation(wrapper.view.layoutIfNeeded)
        return wrapper
    }
    defer {
        // Detach the content VC from the probe wrapper first (so the caller can
        // re-wrap it), then tear the probe wrapper down — including on a hook
        // timeout or cancellation.
        viewController.willMove(toParent: nil)
        viewController.removeFromParent()
        removeChildAfterCapture(probeWrapper)
    }

    if let onReadyToMeasure {
        try await timing.measure(.measurementHook) {
            try await runSnapshotMeasurementHook(
                named: name,
                maximumDuration: measurementHookMaximumDuration,
                hook: onReadyToMeasure,
            )
        }
        timing.measure(.intrinsicMeasure) {
            probeWrapper.view.setNeedsLayout()
            CATransaction.performWithoutAnimation(probeWrapper.view.layoutIfNeeded)
        }
    }

    await reportIfUnsettled(
        timing.measure(.intrinsicMeasure) {
            await settleForCapture(
                probeWrapper.view,
                named: name,
                settle: settle,
                timing: timing,
                timeoutPolicy: settleTimeoutPolicy,
            )
        },
        phase: "content measurement",
        of: viewController,
        named: name,
    )

    func measureIntrinsicContent(width: CGFloat, minimumHeight: CGFloat) -> CGSize {
        var measured = viewController.view
            .sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        measured.width = width
        if !measured.height.isFinite || measured.height <= 0 {
            measured.height = 1
        }
        if let scrollContentHeight = viewController.view.fullScrollContentHeight,
           scrollContentHeight > measured.height
        {
            measured.height = scrollContentHeight
        }
        measured.height = max(measured.height, minimumHeight)
        return measured
    }

    switch sizing {
        case .fixed:
            preconditionFailure("Fixed snapshot sizing must return before measurement.")
        case let .intrinsic(width, minimumHeight):
            let measurement = timing.measure(.intrinsicMeasure) {
                var measured = measureIntrinsicContent(
                    width: width,
                    minimumHeight: minimumHeight,
                )
                var measuredHeights = [measured.height]
                var didConverge = false
                for _ in 0 ..< 10 {
                    viewController.view.frame = CGRect(origin: .zero, size: measured)
                    probeWrapper.view.frame.size = measured
                    CATransaction.performWithoutAnimation(probeWrapper.view.layoutIfNeeded)
                    let remeasured = measureIntrinsicContent(
                        width: width,
                        minimumHeight: minimumHeight,
                    )
                    measuredHeights.append(remeasured.height)
                    if abs(remeasured.height - measured.height) < 0.5 {
                        measured = remeasured
                        didConverge = true
                        break
                    }
                    measured = remeasured
                }
                return (measured, measuredHeights, didConverge)
            }
            guard measurement.2 else {
                throw SnapshotRenderingError.intrinsicHeightDidNotConverge(
                    name: name,
                    measuredHeights: measurement.1,
                )
            }

            timing.measure(.intrinsicMeasure) {
                viewController.view.frame = CGRect(origin: .zero, size: measurement.0)
                CATransaction.performWithoutAnimation(viewController.view.layoutIfNeeded)
            }
        case let .fullContent2D(minimumSize):
            func measureFullContent(proposedSize: CGSize) -> FullContentMeasurement {
                var measured = viewController.view.sizeThatFits(CGSize(
                    width: proposedSize.width,
                    height: .greatestFiniteMagnitude,
                ))
                if !measured.width.isFinite || measured.width <= 0 {
                    measured.width = 1
                }
                if !measured.height.isFinite || measured.height <= 0 {
                    measured.height = 1
                }

                let scrollExtent = viewController.view.viewportFillingScrollContentExtent
                if let scrollExtent {
                    measured.width = max(measured.width, scrollExtent.requiredSize.width)
                    measured.height = max(measured.height, scrollExtent.requiredSize.height)
                }
                measured.width = max(measured.width, minimumSize.width)
                measured.height = max(measured.height, minimumSize.height)
                return FullContentMeasurement(size: measured, scrollView: scrollExtent?.scrollView)
            }

            var measurement = measureFullContent(proposedSize: probeSize)
            var measuredSizes = [measurement.size]
            var didConverge = false
            for _ in 0 ..< 10 {
                try validateTwoAxisCaptureSize(
                    measurement.size,
                    scale: window.screen.scale,
                    named: name,
                )
                timing.measure(.intrinsicMeasure) {
                    viewController.view.frame = CGRect(origin: .zero, size: measurement.size)
                    probeWrapper.view.frame.size = measurement.size
                    CATransaction.performWithoutAnimation(probeWrapper.view.layoutIfNeeded)
                }
                let remeasured = measureFullContent(proposedSize: measurement.size)
                measuredSizes.append(remeasured.size)
                if remeasured.size.isApproximatelyEqual(to: measurement.size) {
                    measurement = remeasured
                    didConverge = true
                    break
                }
                measurement = remeasured
            }
            guard didConverge else {
                throw SnapshotRenderingError.fullContentSizeDidNotConverge(
                    name: name,
                    measuredSizes: measuredSizes,
                )
            }
            try validateTwoAxisCaptureSize(
                measurement.size,
                scale: window.screen.scale,
                named: name,
            )

            timing.measure(.intrinsicMeasure) {
                viewController.view.frame = CGRect(origin: .zero, size: measurement.size)
                CATransaction.performWithoutAnimation(viewController.view.layoutIfNeeded)
                if let scrollView = measurement.scrollView {
                    scrollView.setContentOffset(
                        CGPoint(
                            x: -scrollView.adjustedContentInset.left,
                            y: -scrollView.adjustedContentInset.top,
                        ),
                        animated: false,
                    )
                }
            }
    }
}

private let maximumTwoAxisPixelDimension = 32000
private let maximumTwoAxisPixelCount = 100_000_000

private struct FullContentMeasurement {
    let size: CGSize
    let scrollView: UIScrollView?
}

private struct ScrollContentExtent {
    let scrollView: UIScrollView
    let requiredSize: CGSize
    let viewportArea: CGFloat
}

private func validateTwoAxisCaptureSize(
    _ size: CGSize,
    scale: CGFloat,
    named name: String,
) throws {
    let pixelWidth = boundedPixelDimension(size.width, scale: scale)
    let pixelHeight = boundedPixelDimension(size.height, scale: scale)
    let exceedsPixelCount = pixelHeight > 0
        && pixelWidth > maximumTwoAxisPixelCount / pixelHeight
    guard pixelWidth <= maximumTwoAxisPixelDimension,
          pixelHeight <= maximumTwoAxisPixelDimension,
          !exceedsPixelCount
    else {
        throw SnapshotRenderingError.fullContentSizeExceedsLimit(
            name: name,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            maximumPixelDimension: maximumTwoAxisPixelDimension,
            maximumPixelCount: maximumTwoAxisPixelCount,
        )
    }
}

private func boundedPixelDimension(_ points: CGFloat, scale: CGFloat) -> Int {
    let pixels = ceil(points * scale)
    guard pixels.isFinite, pixels < CGFloat(Int.max) else { return Int.max }
    return max(Int(pixels), 1)
}

extension CGSize {
    fileprivate func isApproximatelyEqual(to other: CGSize) -> Bool {
        abs(width - other.width) < 0.5 && abs(height - other.height) < 0.5
    }
}

extension UIView {
    /// The root height required to show a full-width scrolling descendant's
    /// complete content while preserving the chrome around its viewport.
    ///
    /// `Form` and `List` are backed by UIKit scroll views whose hosting view
    /// answers `sizeThatFits` with only the current viewport. Restricting the
    /// fallback to full-width scrolling content avoids expanding an intentionally
    /// narrow nested scroller inside an otherwise intrinsic component.
    fileprivate var fullScrollContentHeight: CGFloat? {
        descendants
            .compactMap { view -> CGFloat? in
                guard let scrollView = view as? UIScrollView else { return nil }
                let visibleFrame = scrollView.convert(scrollView.bounds, to: self)
                guard visibleFrame.width >= bounds.width - 1,
                      visibleFrame.height > 0,
                      scrollView.contentSize.height.isFinite,
                      scrollView.contentSize.height > 0
                else { return nil }
                let chromeHeight = max(bounds.height - visibleFrame.height, 0)
                let insetHeight = scrollView.adjustedContentInset.top
                    + scrollView.adjustedContentInset.bottom
                return scrollView.contentSize.height + insetHeight + chromeHeight
            }
            .max()
    }

    /// The complete root size required by the largest viewport-filling scroll
    /// descendant. One scroll view owns both axes so an outer spatial canvas is
    /// never combined with the height of an unrelated nested list.
    fileprivate var viewportFillingScrollContentExtent: ScrollContentExtent? {
        descendants
            .compactMap { view -> ScrollContentExtent? in
                guard let scrollView = view as? UIScrollView else { return nil }
                let visibleFrame = scrollView.convert(scrollView.bounds, to: self)
                guard visibleFrame.width >= bounds.width - 1,
                      visibleFrame.height > 0,
                      scrollView.contentSize.width.isFinite,
                      scrollView.contentSize.width > 0,
                      scrollView.contentSize.height.isFinite,
                      scrollView.contentSize.height > 0
                else { return nil }

                let inset = scrollView.adjustedContentInset
                let chromeWidth = max(bounds.width - visibleFrame.width, 0)
                let chromeHeight = max(bounds.height - visibleFrame.height, 0)
                let insetWidth = inset.left + inset.right
                let insetHeight = inset.top + inset.bottom
                return ScrollContentExtent(
                    scrollView: scrollView,
                    requiredSize: CGSize(
                        width: scrollView.contentSize.width + insetWidth + chromeWidth,
                        height: scrollView.contentSize.height + insetHeight + chromeHeight,
                    ),
                    viewportArea: visibleFrame.width * visibleFrame.height,
                )
            }
            .max { lhs, rhs in lhs.viewportArea < rhs.viewportArea }
    }

    private var descendants: [UIView] {
        subviews + subviews.flatMap(\.descendants)
    }
}
