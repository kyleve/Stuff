import CoreGraphics
import Testing
@testable import WhereUI

struct LocationsBackgroundLayoutTests {
    @Test(arguments: [1, 3, 40, 200])
    func everyRegionHasAFullyVisibleCell(count: Int) {
        let size = CGSize(width: 390, height: 844)
        let cells = LocationsBackgroundLayout.cells(count: count, in: size, preferredCellSize: 64)
        let viewport = CGRect(origin: .zero, size: size).insetBy(dx: -0.001, dy: -0.001)
        let visibleRegions = cells.compactMap { cell -> Int? in
            guard viewport.contains(cell.frame) else { return nil }
            return cell.artworkIndex
        }
        #expect(Set(visibleRegions) == Set(0 ..< count))
        #expect(Set(cells.map(\.id)).count == cells.count)
        #expect(cells.allSatisfy { $0.frame.width == $0.frame.height && $0.frame.width > 0 })
    }

    @Test func alternateRowsHaveAHalfCellOffset() throws {
        let cells = LocationsBackgroundLayout.cells(
            count: 5,
            in: CGSize(width: 390, height: 844),
            preferredCellSize: 64,
        )
        let first = try #require(cells.first { abs($0.frame.minY) < 0.001 })
        let second = try #require(cells.first { $0.frame.minY > first.frame.minY })
        let third = try #require(cells.first { $0.frame.minY > second.frame.minY })
        #expect(abs(second.frame.minX - first.frame.minX - first.frame.width / 2) < 0.001)
        #expect(abs(third.frame.minX - first.frame.minX) < 0.001)
    }

    @Test func patternExtendsBeyondEveryEdge() {
        let size = CGSize(width: 390, height: 844)
        let cells = LocationsBackgroundLayout.cells(count: 5, in: size, preferredCellSize: 64)
        #expect(cells.contains { $0.frame.minX < 0 })
        #expect(cells.contains { $0.frame.maxX > size.width })
        #expect(cells.contains { $0.frame.minY < 0 })
        #expect(cells.contains { $0.frame.maxY > size.height })
        for row in Dictionary(grouping: cells, by: { $0.frame.minY }).values {
            for (left, right) in zip(row, row.dropFirst()) {
                #expect(right.artworkIndex == (left.artworkIndex + 1) % 5)
                #expect(abs(left.frame.maxX - right.frame.minX) < 0.001)
            }
        }
    }

    @Test func emptyHistoryAndInvalidSizesProduceNoRegionCells() {
        let size = CGSize(width: 390, height: 844)
        let cells = LocationsBackgroundLayout.cells(count: 0, in: size, preferredCellSize: 64)
        #expect(cells.isEmpty)
        #expect(LocationsBackgroundLayout.cells(count: 3, in: .zero, preferredCellSize: 64).isEmpty)
        #expect(LocationsBackgroundLayout.cells(count: 3, in: size, preferredCellSize: 0).isEmpty)
    }
}
