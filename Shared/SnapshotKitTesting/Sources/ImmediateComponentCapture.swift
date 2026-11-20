import SnapshotKit
import SwiftUI
import UIKit

/// Measures and draws a synchronous component on one native mount. The caller holds the
/// capture lock and supplies a fresh controller for the general renderer if this returns nil.
@MainActor
func captureImmediateComponentIfPossible(
    of controller: UIHostingController<some View>,
    in window: UIWindow,
    configuration: SnapshotConfiguration,
    named name: String,
    timing: SnapshotCaptureTiming,
    timeoutPolicy: SnapshotSettleTimeoutPolicy,
) async throws -> SnapshotCapture? {
    guard case let .intrinsic(.some(width)) = configuration.device.size,
          width > 0, width < tileDimension,
          configuration.device.safeAreaInsets == .zero,
          configuration.device.scenePolicy == .automatic,
          let parent = window.rootViewController
    else { return nil }

    let view = controller.view!
    let initialFrame = view.frame
    let initialRegions = controller.safeAreaRegions
    let animationsWereEnabled = UIView.areAnimationsEnabled
    UIView.setAnimationsEnabled(false)
    controller.safeAreaRegions = []
    controller.traitOverrides[SnapshotCaptureTrait.self] = true
    timing.measure(.host) {
        view.frame = CGRect(x: 0, y: 0, width: width, height: parent.view.bounds.height)
        hostChildForCapture(controller, in: parent)
        view.setNeedsLayout()
        CATransaction.performWithoutAnimation(view.layoutIfNeeded)
    }
    defer {
        removeChildAfterCapture(controller)
        controller.traitOverrides.remove(SnapshotCaptureTrait.self)
        controller.safeAreaRegions = initialRegions
        view.frame = initialFrame
        UIView.setAnimationsEnabled(animationsWereEnabled)
    }

    func layoutAfterYield(_ phase: SnapshotCapturePhase) async throws {
        _ = await timing.measure(phase) {
            await settleForCapture(
                view,
                named: name,
                settle: .immediate,
                timing: timing,
                timeoutPolicy: timeoutPolicy,
            )
        }
        try Task.checkCancellation()
    }

    func componentHeight() -> CGFloat? {
        let proposal = CGSize(width: width, height: .greatestFiniteMagnitude)
        let height = view.sizeThatFits(proposal).height
        // Even a repeatable ideal height can describe a scroll viewport. The general
        // renderer measures its content and restores its top offset before drawing.
        guard height > 0, height < tileDimension,
              view.fullScrollContentHeight(exceeding: 0) == nil else { return nil }
        return height
    }

    try await layoutAfterYield(.intrinsicMeasure)
    guard let height = timing.measure(.intrinsicMeasure, componentHeight) else { return nil }
    timing.measure(.host) {
        view.frame.size = CGSize(width: width, height: height)
        view.setNeedsLayout()
        CATransaction.performWithoutAnimation(view.layoutIfNeeded)
    }
    try await layoutAfterYield(.settle)
    guard timing.measure(.intrinsicMeasure, componentHeight) == height else { return nil }
    view.hideTextInputCursors()
    timing.measure(.drain) { drainInFlightAnimations() }
    return try autoreleasepool {
        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .standard
        format.scale = window.traitCollection.displayScale
        var complete = false
        let image = timing.measure(.tileStitch) {
            UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
                complete = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
        }
        guard complete, let pixels = image.cgImage else { return nil }
        let capture = try timing.measure(.pngRoundTrip) {
            try SnapshotCapture(normalizing: image, named: name)
        }
        timing.recordCaptureShape(tiles: 1, pixels: pixels.width * pixels.height)
        timing.captureMode = .immediateComponent
        return capture
    }
}
