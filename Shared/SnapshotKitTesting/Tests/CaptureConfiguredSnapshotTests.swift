import SnapshotKit
@_spi(Testing) @testable import SnapshotKitTesting
import SwiftUI
import Testing

@MainActor
struct CaptureConfiguredSnapshotTests {
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
