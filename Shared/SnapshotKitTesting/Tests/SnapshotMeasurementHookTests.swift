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
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
