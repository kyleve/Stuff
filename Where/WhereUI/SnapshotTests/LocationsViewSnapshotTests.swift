import SnapshotKitTesting
import SwiftUI
import Testing
@_spi(Testing) @testable import WhereUI

@MainActor
struct LocationsViewSnapshotTests {
    @Test func locations() async {
        await assertSnapshots(of: LocationsView.self)
    }

    @Test func adaptiveLoadStates() async throws {
        for state in AdaptivePaneLoadFixture.State.allCases {
            for pose in [SnapshotConfiguration.Pose.innerPortrait, .tabletop] {
                let fixture = try await AdaptivePaneLoadFixture(state: state)
                await assertSnapshots(
                    of: LocationsView(report: fixture.report)
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
}
