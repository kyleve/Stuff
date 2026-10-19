import Foundation
import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct LocationsViewSnapshotTests {
    @Test func locations() async {
        await assertSnapshots(of: LocationsView.self)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_PROBE"] == "1"))
    func settlingProbe() async throws {
        for iteration in 1 ... 32 {
            print("SNAPSHOT_PROBE Locations \(iteration)/32")
            let snapshot = try #require(LocationsView.snapshots
                .first { $0.name == "Flight-FlightLikely" })
            let configuration = try #require(snapshot.configurations
                .first { $0.identifier == "iPhone_ax5" })
            await assertSnapshots(
                of: snapshot.content,
                named: snapshot.name,
                configurations: [configuration],
                measurementReadiness: snapshot.measurementReadiness,
                onReadyToMeasure: snapshot.onReadyToMeasure,
                settle: snapshot.settle,
                onReadyToSnapshot: snapshot.onReadyToSnapshot,
                record: .never,
                testName: "locations()",
            )
        }
    }
}
