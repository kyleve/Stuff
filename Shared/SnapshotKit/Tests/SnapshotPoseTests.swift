import SnapshotKit
import Testing

struct SnapshotPoseTests {
    @Test func foldsReuseFramesWithoutChangingCaptureIdentity() {
        #expect(SnapshotConfiguration(device: SnapshotConfiguration.Pose.tabletop.frame)
            .identifier == "duoInnerPortrait")
        #expect(SnapshotConfiguration(device: SnapshotConfiguration.Pose.book.frame)
            .identifier == "duoInnerLandscape")
        #expect(SnapshotConfiguration.Pose.tabletop.size == SnapshotConfiguration.Pose.innerPortrait
            .size)
        #expect(SnapshotConfiguration.Pose.book.size == SnapshotConfiguration.Pose.innerLandscape
            .size)
    }

    @Test func foldingActivatesTheSameReservedDivision() throws {
        for pair in [
            [SnapshotConfiguration.Pose.innerPortrait, .tabletop],
            [.innerLandscape, .book],
        ] {
            let flat = try #require(pair[0].reservedRegions.first)
            let folded = try #require(pair[1].reservedRegions.first)
            #expect(flat.frame == folded.frame)
            #expect(!flat.isActive)
            #expect(folded.isActive)
            #expect(folded.kind == .division)
        }
        #expect(SnapshotConfiguration.Pose.outerPortrait.reservedRegions.isEmpty)
        #expect(SnapshotConfiguration.Pose.outerLandscape.reservedRegions.isEmpty)
        #expect(SnapshotConfiguration.Pose.narrow.reservedRegions.isEmpty)
    }
}
