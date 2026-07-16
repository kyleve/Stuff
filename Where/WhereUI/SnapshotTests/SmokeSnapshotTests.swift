import SnapshotKitTesting
import SwiftUI
import Testing

/// Smoke test proving the snapshot pipeline is wired end to end: the
/// `SnapshotKitTesting` dependency resolves, the bundle builds and runs in the
/// host, a reference image is written under `__Snapshots__/`, and Git LFS stores
/// it. Superseded by the real matrixed coverage but kept as a minimal canary.
@MainActor
@Suite(.snapshots(record: .missing))
struct SmokeSnapshotTests {
    @Test func rendersASolidSwatch() {
        let swatch = Rectangle()
            .fill(.blue)
            .frame(width: 40, height: 40)
        assertSnapshot(of: swatch, as: .image(layout: .fixed(width: 40, height: 40)))
    }
}
