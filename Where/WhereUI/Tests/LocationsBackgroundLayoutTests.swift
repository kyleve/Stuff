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
            guard viewport.contains(cell.frame),
                  case let .region(index) = cell.motif else { return nil }
            return index
        }
        #expect(Set(visibleRegions) == Set(0 ..< count))
        #expect(Set(cells.map(\.id)).count == cells.count)
        #expect(cells.allSatisfy { $0.frame.width == $0.frame.height && $0.frame.width > 0 })
    }

    @Test func rosettesAlternateWithRegionsOnTheDiagonal() {
        let cells = LocationsBackgroundLayout.cells(
            count: 5,
            in: CGSize(width: 390, height: 844),
            preferredCellSize: 64,
        )
        for pair in stride(from: 0, to: cells.count, by: 2) {
            let region = cells[pair]
            let rosette = cells[pair + 1]
            guard case .region = region.motif else {
                Issue.record("Expected a region before each rosette")
                return
            }
            #expect(rosette.motif == .rosette)
            #expect(abs(rosette.frame.midX - region.frame.midX - region.frame.width / 2) < 0.001)
            #expect(abs(rosette.frame.midY - region.frame.midY - region.frame.height / 2) < 0.001)
        }
    }

    @Test func patternExtendsBeyondEveryEdge() {
        let size = CGSize(width: 390, height: 844)
        let cells = LocationsBackgroundLayout.cells(count: 5, in: size, preferredCellSize: 64)
        let rosettes = cells.filter { $0.motif == .rosette }
        #expect(rosettes.contains { $0.frame.minX < 0 && $0.frame.maxX > 0 })
        #expect(rosettes.contains { $0.frame.minX < size.width && $0.frame.maxX > size.width })
        #expect(rosettes.contains { $0.frame.minY < 0 && $0.frame.maxY > 0 })
        #expect(rosettes.contains { $0.frame.minY < size.height && $0.frame.maxY > size.height })
    }

    @Test func emptyHistoryKeepsOnlyRosettesAndInvalidSizesProduceNoCells() {
        let size = CGSize(width: 390, height: 844)
        let cells = LocationsBackgroundLayout.cells(count: 0, in: size, preferredCellSize: 64)
        #expect(!cells.isEmpty)
        #expect(cells.allSatisfy { $0.motif == .rosette })
        #expect(LocationsBackgroundLayout.cells(count: 3, in: .zero, preferredCellSize: 64).isEmpty)
        #expect(LocationsBackgroundLayout.cells(count: 3, in: size, preferredCellSize: 0).isEmpty)
    }
}
