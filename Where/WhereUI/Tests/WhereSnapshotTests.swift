import SwiftUI
import Testing
@testable import WhereUI

@MainActor
struct WhereSnapshotTests {
    @Test func forwardsMeasurementAndCaptureReadinessHooks() async {
        var readinessCalls = 0
        let snapshot = whereSnapshot(
            name: "Readiness",
            configurations: .fullContentPhoneLightDark,
            onReadyToMeasure: { readinessCalls += 1 },
            onReadyToSnapshot: { readinessCalls += 10 },
        ) {
            Text("Ready")
        }

        await snapshot.onReadyToMeasure?()
        #expect(readinessCalls == 1)
        await snapshot.onReadyToSnapshot?()
        #expect(readinessCalls == 11)
    }
}
