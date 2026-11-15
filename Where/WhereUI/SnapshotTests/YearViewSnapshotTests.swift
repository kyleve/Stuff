import SnapshotKitTesting
import SwiftUI
import Testing
@_spi(Testing) @testable import WhereUI

@MainActor
struct YearViewSnapshotTests {
    @Test func year() async {
        await assertSnapshots(of: YearView.self)
    }

    @Test func adaptiveLoadStates() async throws {
        let pose = SnapshotConfiguration.DuoPose.innerPortrait
        for state in AdaptivePaneLoadFixture.State.allCases {
            let fixture = try await AdaptivePaneLoadFixture(state: state)
            await assertSnapshots(
                of: YearView(report: fixture.report)
                    .adaptivePaneReservedRegions(pose.regions)
                    .whereBroadwayRoot(),
                named: "Adaptive-" + state.rawValue + "-" + pose.rawValue,
                configurations: [SnapshotConfiguration(device: pose.frame)],
                settle: .settledAtLeast(minDuration: 1),
            )
            await fixture.finish()
        }
    }
}
