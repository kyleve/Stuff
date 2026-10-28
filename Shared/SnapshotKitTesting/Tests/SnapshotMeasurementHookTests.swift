import Foundation
@_spi(Testing) import SnapshotKitTesting
import Testing

@MainActor
struct SnapshotMeasurementHookTests {
    @Test func completedHookReturnsBeforeItsBudget() async throws {
        var didRun = false

        try await runSnapshotMeasurementHook(named: "complete", maximumDuration: 1) {
            didRun = true
        }

        #expect(didRun)
    }

    @Test func timedOutHookThrowsTheCaptureError() async {
        await #expect(
            throws: SnapshotRenderingError.measurementReadinessTimedOut(
                name: "timeout",
                budget: 0.02,
            ),
        ) {
            try await runSnapshotMeasurementHook(named: "timeout", maximumDuration: 0.02) {
                try await Task.sleep(for: .seconds(60))
            }
        }
    }

    @Test func throwingHookPreservesItsError() async {
        await #expect(throws: URLError(.cannotConnectToHost)) {
            try await runSnapshotMeasurementHook(named: "failure", maximumDuration: 1) {
                throw URLError(.cannotConnectToHost)
            }
        }
    }

    @Test(arguments: [0.0, -1.0, Double.infinity, Double.nan])
    func invalidTimeoutDoesNotRunHook(timeout: Double) async {
        var didRun = false
        await #expect(throws: SnapshotRenderingError.self) {
            try await runSnapshotMeasurementHook(named: "invalid", maximumDuration: timeout) {
                didRun = true
            }
        }
        #expect(!didRun)
    }
}
