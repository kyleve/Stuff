import SnapshotKit
import SwiftUI
import TestHostSupport
import UIKit

/// PNG bytes and dimensions from a hosted capture without a reference compare.
public struct SnapshotPNG: Sendable {
    public let data: Data
    public let pointSize: CGSize
    public let pixelSize: CGSize
    public let scale: CGFloat

    public init(data: Data, pointSize: CGSize, pixelSize: CGSize, scale: CGFloat) {
        self.data = data
        self.pointSize = pointSize
        self.pixelSize = pixelSize
        self.scale = scale
    }
}

/// Captures a configured SwiftUI view through the hosted snapshot pipeline.
@MainActor
public func captureSnapshotPNG(
    of view: some View,
    configuration: SnapshotConfiguration,
    named name: String,
    sizing: SnapshotSizing,
    safeAreaInsets: UIEdgeInsets?,
    measurementReadiness: SnapshotMeasurementReadiness,
    onReadyToMeasure: (@MainActor () async -> Void)?,
    settle: SnapshotSettle,
    onReadyToSnapshot: (@MainActor () async -> Void)?,
) async throws -> SnapshotPNG {
    try waitFor { hostKeyWindow()?.rootViewController != nil }
    let controller = makeHostingController(for: view, configuration: configuration)
    let timeoutPolicy = try SnapshotSettleTimeoutPolicy.fromEnvironment()
    let capture = try await renderSnapshotCapture(
        of: controller,
        named: name,
        sizing: sizing,
        safeAreaInsets: safeAreaInsets,
        isAccessibility: configuration.snapshotType == .accessibility,
        measurementReadiness: measurementReadiness,
        onReadyToMeasure: onReadyToMeasure,
        settle: settle,
        onReadyToSnapshot: onReadyToSnapshot,
        settleTimeoutPolicy: timeoutPolicy,
        timing: SnapshotCaptureTiming(identifier: name, isEnabled: false),
    )
    guard let image = capture.image.cgImage else {
        throw SnapshotRenderingError.missingCGImage(name: name)
    }
    return SnapshotPNG(
        data: capture.pngData,
        pointSize: capture.image.size,
        pixelSize: CGSize(width: image.width, height: image.height),
        scale: capture.image.scale,
    )
}
