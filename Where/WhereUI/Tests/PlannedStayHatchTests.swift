import SwiftUI
import Testing
@testable import WhereUI

struct PlannedStayHatchTests {
    @Test func cellsShareOneStripeLattice() {
        let height: CGFloat = 44
        let spacing: CGFloat = 6
        let cellWidth: CGFloat = 105.5
        let gridSpacing: CGFloat = 6

        for column in 0 ..< 7 {
            let extendLeading = column == 0 ? 0 : gridSpacing / 2
            let origin = CGFloat(column) * (cellWidth + gridSpacing) - extendLeading
            let firstLine = PlannedStayHatch.firstLineX(
                height: height,
                gridOriginX: origin,
                spacing: spacing,
            )
            let globalStripePosition = origin + firstLine + height

            #expect(abs(globalStripePosition.truncatingRemainder(dividingBy: spacing)) < 0.000_001)
        }
    }
}
