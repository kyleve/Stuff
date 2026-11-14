import SnapshotKit
import Testing

struct SnapshotDuoPoseTests {
    @Test func foldsReuseFramesWithoutChangingCaptureIdentity() {
        #expect(SnapshotConfiguration(device: SnapshotConfiguration.DuoPose.tabletop.frame)
            .identifier == "duoInnerPortrait")
        #expect(SnapshotConfiguration(device: SnapshotConfiguration.DuoPose.book.frame)
            .identifier == "duoInnerLandscape")
        #expect(SnapshotConfiguration.DuoPose.tabletop.size == SnapshotConfiguration.DuoPose
            .innerPortrait
            .size)
        #expect(SnapshotConfiguration.DuoPose.book.size == SnapshotConfiguration.DuoPose
            .innerLandscape
            .size)
    }

    @Test func foldingActivatesTheSameReservedDivision() throws {
        for pair in [
            [SnapshotConfiguration.DuoPose.innerPortrait, .tabletop],
            [.innerLandscape, .book],
        ] {
            let flat = try #require(pair[0].reservedRegions.first)
            let folded = try #require(pair[1].reservedRegions.first)
            #expect(flat.frame == folded.frame)
            #expect(!flat.isActive)
            #expect(folded.isActive)
            #expect(folded.kind == .division)
        }
        #expect(SnapshotConfiguration.DuoPose.outerPortrait.reservedRegions.isEmpty)
        #expect(SnapshotConfiguration.DuoPose.outerLandscape.reservedRegions.isEmpty)
        #expect(SnapshotConfiguration.DuoPose.narrow.reservedRegions.isEmpty)
    }
}
