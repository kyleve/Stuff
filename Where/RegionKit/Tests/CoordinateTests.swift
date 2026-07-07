@testable import RegionKit
import Testing

struct CoordinateTests {
    @Test func ringNeedsAtLeastThreeVertices() {
        let vertex = Coordinate(latitude: 0, longitude: 0)
        #expect([Coordinate]().isValidPolygonRing == false)
        #expect([vertex].isValidPolygonRing == false)
        #expect([vertex, vertex].isValidPolygonRing == false)
        #expect([vertex, vertex, vertex].isValidPolygonRing)
        #expect(Array(repeating: vertex, count: 12).isValidPolygonRing)
    }
}
