import Foundation
@testable import InstallerKitUI
import SnapshotKitTesting
import Testing

@MainActor
struct UpdateHistoryViewSnapshotTests {
    @Test func history() async {
        await assertSnapshots(of: UpdateHistoryView.self)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_PROBE"] == "1"))
    func settlingProbe() async throws {
        for iteration in 1 ... 32 {
            print("SNAPSHOT_PROBE UpdateHistory \(iteration)/32")
            let snapshot = try #require(UpdateHistoryView.snapshots.first { $0.name == "History" })
            let configuration = try #require(snapshot.configurations
                .first { $0.identifier == "iPad" })
            await assertSnapshots(
                of: snapshot.content,
                named: snapshot.name,
                configurations: [configuration],
                measurementReadiness: snapshot.measurementReadiness,
                onReadyToMeasure: snapshot.onReadyToMeasure,
                settle: snapshot.settle,
                onReadyToSnapshot: snapshot.onReadyToSnapshot,
                record: .never,
                testName: "history()",
            )
        }
    }
}
