import SnapshotKit
@_spi(Testing) @testable import SnapshotKitTesting
import SwiftUI
import Testing

@MainActor
struct CaptureConfiguredSnapshotTests {
    @Test func componentOptInHonorsCaptureHooks() async throws {
        var hooks = [String]()
        let result = try await captureConfiguredSnapshot(
            of: Color.green.frame(height: 20),
            configuration: SnapshotConfiguration(device: .component),
            named: "component-with-hooks",
            measurementReadiness: .sameAsCapture,
            onReadyToMeasure: nil,
            measurementHookTimeout: nil,
            settle: .immediate,
            prepareForCapture: { hooks.append("prepare") },
            onReadyToSnapshot: { hooks.append("ready") },
            captureMode: .immediateComponent,
            timeoutPolicy: .init(multiplier: 1),
        )
        #expect(result.timing.captureMode == .standard)
        #expect(hooks == ["prepare", "ready"])
    }

    @Test func sharedCaptureRetriesSettlingBeforeReturningPixels() async throws {
        var attempts = 0
        let result = try await captureConfiguredSnapshot(
            of: Color.green.frame(width: 40, height: 40),
            configuration: SnapshotConfiguration(),
            named: "configured-retry",
            measurementReadiness: .immediate,
            onReadyToMeasure: {
                attempts += 1
                if attempts < 3 { throw snapshotRetryTimeout(attempt: attempts) }
            },
            measurementHookTimeout: nil,
            settle: .immediate,
            onReadyToSnapshot: nil,
            timeoutPolicy: .init(multiplier: 1),
        )
        #expect(attempts == 3)
        #expect(result.capture.image.cgImage != nil)
    }
}
