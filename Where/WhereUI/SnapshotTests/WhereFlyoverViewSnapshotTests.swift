import Flyover
import SnapshotKit
import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct WhereFlyoverViewSnapshotTests {
    @Test func seededEntryState() async throws {
        let world = try await WhereFlyoverWorld.build()

        await assertSnapshots(
            of: FlyoverView(catalog: WhereFlyoverCatalog.make(world: world)),
            named: "WhereFlyover",
            configurations: SnapshotConfiguration.combinations(
                devices: [.iPadFullContent2D],
                colorSchemes: [.light],
            ),
            // Flyover intentionally hosts many independent screen trees whose
            // async tasks do not quiesce as one unit. The world is fully loaded
            // before hosting and the overview substitutes deterministic capture
            // states, so one layout/task yield is the stable entry frame.
            settle: .immediate,
        )
    }
}
