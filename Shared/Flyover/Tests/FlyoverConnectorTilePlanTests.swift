import CoreGraphics
@testable import Flyover
import Testing

struct FlyoverConnectorTilePlanTests {
    @Test func partitionsTheOversizedWhereGraphIntoBoundedSurfaces() throws {
        // The previous full-graph Canvas requested an 18000×6768-pixel texture
        // on iPad and dropped every connector when that allocation failed.
        let size = CGSize(width: 9000, height: 3384)
        let tiles = FlyoverConnectorTilePlan(canvasSize: size).tiles

        #expect(tiles.count == 36)
        #expect(Set(tiles.map(\.id)).count == tiles.count)
        #expect(tiles.allSatisfy {
            $0.frame.width <= FlyoverConnectorTilePlan.maximumDimension
                && $0.frame.height <= FlyoverConnectorTilePlan.maximumDimension
        })
        #expect(tiles.reduce(CGRect.null) { $0.union($1.frame) } == CGRect(
            origin: .zero,
            size: size,
        ))
        #expect(tiles.reduce(0) { $0 + $1.frame.width * $1.frame.height } == size.width * size
            .height)
        for (index, tile) in tiles.enumerated() {
            #expect(tiles.dropFirst(index + 1).allSatisfy {
                tile.frame.intersection($0.frame).isEmpty
            })
        }

        let last = try #require(tiles.last)
        #expect(last.frame == CGRect(x: 8192, y: 3072, width: 808, height: 312))
    }

    @Test func retainsFractionalEdgeCoverageAndStableTileIdentities() {
        let size = CGSize(width: 1024.5, height: 2048.25)
        let initial = FlyoverConnectorTilePlan(canvasSize: size).tiles
        let expanded = FlyoverConnectorTilePlan(canvasSize: CGSize(width: 1500, height: 2500)).tiles
        let expectedArea: CGFloat = size.width * size.height
        let actualArea: CGFloat = initial.reduce(0) { $0 + $1.frame.width * $1.frame.height }

        #expect(initial.count == 6)
        #expect(initial.map(\.id) == expanded.map(\.id))
        #expect(initial.last?.frame == CGRect(x: 1024, y: 2048, width: 0.5, height: 0.25))
        #expect(actualArea == expectedArea)
    }

    @Test func exactMultiplesDoNotCreateEmptyEdgeTiles() {
        let tiles = FlyoverConnectorTilePlan(canvasSize: CGSize(width: 2048, height: 1024)).tiles

        #expect(tiles.count == 2)
        #expect(tiles.allSatisfy { $0.frame.size == CGSize(width: 1024, height: 1024) })
    }

    @Test(arguments: [CGSize.zero, CGSize(width: 0, height: 100), CGSize(width: 100, height: 0)])
    func emptyCanvasHasNoDrawingSurfaces(size: CGSize) {
        #expect(FlyoverConnectorTilePlan(canvasSize: size).tiles.isEmpty)
    }
}
