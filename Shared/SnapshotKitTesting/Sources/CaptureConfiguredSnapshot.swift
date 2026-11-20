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
    prepareForCapture: (@MainActor () async throws -> Void)? = nil,
    onReadyToSnapshot: (@MainActor () async -> Void)?,
    captureMode: SnapshotCaptureMode = .standard,
    timeoutPolicy: SnapshotSettleTimeoutPolicy,
    backgroundColor: UIColor = .clear,
) async throws -> ConfiguredSnapshotCapture {
    var retainedTiming: SnapshotCaptureTiming?
    return try await SnapshotCaptureRetry.capture(named: name, operation: {
        try await SnapshotCaptureLock.withHost { window in
            let sizing: SnapshotSizing = switch configuration.device.size {
                case .fixed: .fixed
                case let .intrinsic(width): .intrinsic(
                        width: width ?? window.bounds.width,
                        minimumHeight: 0,
                    )
                case let .fullContent(width, minimumHeight): .intrinsic(
                        width: width,
                        minimumHeight: minimumHeight ?? 0,
                    )
                case let .fullContent2D(minimumSize): .fullContent2D(minimumSize: minimumSize)
            }
            let timing = retainedTiming ?? SnapshotCaptureTiming(
                identifier: name,
                isEnabled: SnapshotCaptureTiming.isEnabledByEnvironment,
                sizing: sizing,
                measurementReadiness: measurementReadiness,
                captureSettle: settle,
            )
            retainedTiming = timing
            timing.captureMode = .standard
            let makeController = {
                let controller = makeHostingController(
                    for: view,
                    configuration: configuration,
                    hostWidth: window.bounds.width,
                )
                controller.view.backgroundColor = backgroundColor
                return controller
            }
            if captureMode == .immediateComponent,
               configuration.snapshotType == .standard,
               settle == .immediate,
               measurementReadiness.resolvedSettle(captureSettle: settle) == .immediate,
               onReadyToMeasure == nil, prepareForCapture == nil, onReadyToSnapshot == nil,
               let capture = try await captureImmediateComponentIfPossible(
                   of: makeController(),
                   in: window,
                   configuration: configuration,
                   named: name,
                   timing: timing,
                   timeoutPolicy: timeoutPolicy,
               )
            {
                return ConfiguredSnapshotCapture(capture: capture, timing: timing)
            }
            let capture = try await renderSnapshotCaptureLocked(
                of: makeController(),
                hostWindow: window,
                named: name,
                sizing: sizing,
                safeAreaInsets: configuration.device.safeAreaInsets.uiEdgeInsets,
                scenePolicy: configuration.device.scenePolicy,
                isAccessibility: configuration.snapshotType == .accessibility,
                measurementReadiness: measurementReadiness,
                onReadyToMeasure: onReadyToMeasure,
                measurementHookTimeout: measurementHookTimeout,
                settle: settle,
                captureAfterMeasurement: captureMode == .afterMeasurement,
                prepareForCapture: prepareForCapture,
                onReadyToSnapshot: onReadyToSnapshot,
                settleTimeoutPolicy: timeoutPolicy,
                timing: timing,
            )
            return ConfiguredSnapshotCapture(capture: capture, timing: timing)
        }
    }, report: { print($0) })
}
