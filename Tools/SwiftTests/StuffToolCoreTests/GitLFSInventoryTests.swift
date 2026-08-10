import Foundation
import StuffToolCore
import Testing

struct GitLFSInventoryTests {
    @Test func reportsOnlyUnhydratedSnapshotPNGReferences() throws {
        let inventory = try JSONDecoder().decode(
            GitLFSInventory.self,
            from: fixtureData("git-lfs-files", extension: "json"),
        )

        #expect(inventory.unhydratedSnapshotReferences == [
            "Feature/SnapshotTests/__Snapshots__/CardTests/card.dark.png",
        ])
    }
}
