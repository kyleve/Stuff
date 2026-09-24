import CoreGraphics
import Testing
@testable import WhereUI

struct LocationsBackgroundLayoutTests {
    @Test(arguments: [1, 3, 40, 200])
    func everyRegionFitsInsideTheViewport(count: Int) {
        let size = CGSize(width: 390, height: 844)
        let cells = LocationsBackgroundLayout.cells(count: count, in: size, preferredCellSize: 140)
        #expect(Set(cells.map(\.artworkIndex)) == Set(0 ..< count))
        #expect(Set(cells.map(\.id)).count == cells.count)
        for cell in cells {
            #expect(cell.frame.minX >= 0)
            #expect(cell.frame.minY >= 0)
            #expect(cell.frame.maxX <= size.width + 0.001)
            #expect(cell.frame.maxY <= size.height + 0.001)
            #expect(cell.frame.width > 0 && cell.frame.height > 0)
        }
    }

    @Test func smallSetsRepeatAndEmptyInputsProduceNoCells() {
        let size = CGSize(width: 390, height: 844)
        #expect(LocationsBackgroundLayout.cells(count: 1, in: size, preferredCellSize: 140)
            .count > 1)
        #expect(LocationsBackgroundLayout.cells(count: 0, in: size, preferredCellSize: 140).isEmpty)
        #expect(LocationsBackgroundLayout.cells(count: 3, in: .zero, preferredCellSize: 140)
            .isEmpty)
    }
}
