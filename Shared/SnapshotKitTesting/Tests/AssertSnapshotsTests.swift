import SnapshotKit
import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing

@MainActor
struct AssertSnapshotsTests {
    @Test func cancellationDuringMeasurementReadinessEndsQuietly() async throws {
        try waitFor { hostKeyWindow() != nil }
        let probe = MeasurementHookCancellationProbe()
        let assertion = Task { @MainActor in
            await assertSnapshots(
                of: Color.green.frame(width: 100, height: 100),
                named: "cancelled-measurement-readiness",
                configurations: [SnapshotConfiguration()],
                measurementReadiness: .immediate,
                onReadyToMeasure: {
                    probe.didStart = true
                    while Task.isCancelled == false {
                        await Task.yield()
                    }
                },
                settle: .immediate,
            )
        }

        while probe.didStart == false {
            await Task.yield()
        }
        assertion.cancel()
        await assertion.value
    }
}

@MainActor
private final class MeasurementHookCancellationProbe {
    var didStart = false
}
