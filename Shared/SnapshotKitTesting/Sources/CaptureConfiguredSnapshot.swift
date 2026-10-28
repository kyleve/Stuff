import SnapshotKit
import SwiftUI
import UIKit

/// Keeps timing attached to its capture until the caller finishes comparison.
struct ConfiguredSnapshotCapture {
    let capture: SnapshotCapture
    let timing: SnapshotCaptureTiming
}

/// Resolves matrix sizing once for both individual views and independent cutsheet panels.
@MainActor
func captureConfiguredSnapshot(
    of view: some View,
    configuration: SnapshotConfiguration,
    named name: String,
    measurementReadiness: SnapshotMeasurementReadiness,
    onReadyToMeasure: (@MainActor () async throws -> Void)?,
    measurementHookTimeout: TimeInterval?,
    settle: SnapshotSettle,
    onReadyToSnapshot: (@MainActor () async -> Void)?,
    timeoutPolicy: SnapshotSettleTimeoutPolicy,
    backgroundColor: UIColor = .clear,
) async throws -> ConfiguredSnapshotCapture {
    let sizing: SnapshotSizing = switch configuration.device.size {
        case .fixed: .fixed
        case let .intrinsic(width): .intrinsic(
                width: width ?? UIScreen.main.bounds.width,
                minimumHeight: 0,
            )
        case let .fullContent(width, minimumHeight): .intrinsic(
                width: width,
                minimumHeight: minimumHeight ?? 0,
            )
        case let .fullContent2D(minimumSize): .fullContent2D(minimumSize: minimumSize)
    }
    let timing = SnapshotCaptureTiming(
        identifier: name,
        isEnabled: SnapshotCaptureTiming.isEnabledByEnvironment,
        sizing: sizing,
        measurementReadiness: measurementReadiness,
        captureSettle: settle,
    )
    let capture = try await SnapshotCaptureRetry.capture(
        named: name,
        makeViewController: {
            let controller = makeHostingController(for: view, configuration: configuration)
            controller.view.backgroundColor = backgroundColor
            return controller
        },
        capture: { controller in
            try await renderSnapshotCapture(
                of: controller,
                named: name,
                sizing: sizing,
                safeAreaInsets: configuration.device.safeAreaInsets.uiEdgeInsets,
                isAccessibility: configuration.snapshotType == .accessibility,
                measurementReadiness: measurementReadiness,
                onReadyToMeasure: onReadyToMeasure,
                measurementHookTimeout: measurementHookTimeout,
                settle: settle,
                onReadyToSnapshot: onReadyToSnapshot,
                settleTimeoutPolicy: timeoutPolicy,
                timing: timing,
            )
        },
        report: { print($0) },
    )
    return ConfiguredSnapshotCapture(capture: capture, timing: timing)
}
