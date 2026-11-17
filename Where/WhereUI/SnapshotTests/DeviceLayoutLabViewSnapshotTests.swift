@_spi(Capture) import SnapshotKit
import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.serialized)
struct DeviceLayoutLabViewSnapshotTests {
    @Test func deviceLayoutLab() async {
        await assertSnapshots(of: SharedWorldSnapshots.self)
    }

    private enum SharedWorldSnapshots: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            DeviceLayoutLabView.snapshots(buildWorld: SnapshotWorldFixture.shared.load)
        }
    }

    @Test func preloadedTabletMatchesTheColdStartReference() async throws {
        let frame = SnapshotConfiguration.DeviceProfile.iPadPro13.frame(orientation: .landscape)
        let snapshot = try #require(DeviceLayoutLabView.snapshots.first { $0.name == frame.name })
        // Retries reuse the loaded model while constructing a fresh controller.
        await snapshot.onReadyToSnapshot?()
        guard case let .single(content) = snapshot.capture else {
            Issue.record("The tablet lab must be a single scene capture")
            return
        }
        await assertSnapshots(
            of: content(),
            named: snapshot.name,
            configurations: snapshot.configurations,
            referenceGroup: snapshot.referenceGroup,
            measurementReadiness: snapshot.measurementReadiness,
            onReadyToMeasure: snapshot.onReadyToMeasure,
            settle: snapshot.settle,
            onReadyToSnapshot: snapshot.onReadyToSnapshot,
            testName: "deviceLayoutLab",
        )
    }
}
