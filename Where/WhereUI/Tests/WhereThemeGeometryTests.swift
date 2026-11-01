import Foundation
import Testing
@testable import WhereUI

struct WhereThemeGeometryTests {
    @Test func pointRoundTripsSignedCoordinates() throws {
        let value = WhereThemePoint(x: -12, y: 8)
        #expect(try JSONDecoder()
            .decode(WhereThemePoint.self, from: JSONEncoder().encode(value)) == value)
        #expect(value.point.x == -12)
        try WhereThemeValidation.validate(value, path: "center")
    }

    @Test func sizeRejectsNegativeExtents() {
        #expect(throws: WhereThemeValidationError.self) { try WhereThemeValidation.validate(
            WhereThemeSize(width: -1, height: 10),
            path: "extent",
        ) }
    }
}
