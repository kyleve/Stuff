import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct ProjectionSurfaceSnapshotTests {
    @Test func projectionSurface() async {
        await assertSnapshots(of: ProjectionSurface.self)
    }
}
