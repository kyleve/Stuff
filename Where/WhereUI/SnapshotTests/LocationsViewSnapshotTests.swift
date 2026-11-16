@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import Testing
@_spi(Testing) @testable import WhereUI

@MainActor
struct LocationsViewSnapshotTests {
    @Test func locations() async {
        await assertSnapshots(of: LocationsView.self)
    }

    @Test(arguments: [AdaptivePaneLoadFixture.State.loading, .failed])
    func initialStateHasOneNavigationBarAndOneTopInset(state: AdaptivePaneLoadFixture
        .State) async throws
    {
        let fixture = try await AdaptivePaneLoadFixture(state: state)
        let host = UIHostingController(rootView: LocationsView(report: fixture.report)
            .whereBroadwayRoot())
        host.traitOverrides.horizontalSizeClass = .regular
        host.traitOverrides.verticalSizeClass = .regular
        host.traitOverrides.userInterfaceIdiom = .phone
        host.view.frame = CGRect(x: 0, y: 0, width: 669, height: 951)
        _ = try await renderSnapshotImage(
            of: host,
            named: "locations-initial-state-insets",
            sizing: .fixed,
            safeAreaInsets: UIEdgeInsets(top: 82, left: 0, bottom: 34, right: 0),
            onReadyToSnapshot: {
                func controllers(_ root: UIViewController) -> [UIViewController] {
                    [root] + root.children.flatMap(controllers)
                }
                let bars = controllers(host)
                    .compactMap { ($0 as? UINavigationController)?.navigationBar }
                #expect(bars.count == 1)
                for bar in bars {
                    let frame = bar.convert(bar.bounds, to: host.view)
                    #expect(frame.minY >= 82 && frame.minY <= 90, "Native bar frame: \(frame)")
                }
            },
        )
        await fixture.finish()
    }

    @Test func adaptiveLoadStates() async throws {
        let pose = SnapshotConfiguration.DuoPose.innerPortrait
        for state in AdaptivePaneLoadFixture.State.allCases {
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
