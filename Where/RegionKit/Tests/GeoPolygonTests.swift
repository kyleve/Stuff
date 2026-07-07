@testable import RegionKit
import Testing

struct GeoPolygonTests {
    /// A 1° × 1° square centered on (37.5, -122.5): lat 37–38, lng -123 to -122.
    private static let square = GeoPolygon(vertices: [
        Coordinate(latitude: 37.0, longitude: -123.0),
        Coordinate(latitude: 38.0, longitude: -123.0),
        Coordinate(latitude: 38.0, longitude: -122.0),
        Coordinate(latitude: 37.0, longitude: -122.0),
    ])

    @Test func distanceToBoundary_pointOnEdge_isZero() {
        let onEdge = Coordinate(latitude: 37.5, longitude: -123.0)
        #expect(Self.square.distanceToBoundary(from: onEdge) == 0)
    }

    @Test func distanceToBoundary_pointInside_isPositive() {
        let inside = Coordinate(latitude: 37.5, longitude: -122.5)
        let distance = Self.square.distanceToBoundary(from: inside)
        #expect(distance > 0)
        // Roughly 0.5° latitude ≈ 55 km to the nearest edge.
        #expect(distance > 40000)
        #expect(distance < 70000)
    }

    @Test func distanceToBoundary_pointOutside_isGreaterThanInside() {
        let inside = Coordinate(latitude: 37.5, longitude: -122.5)
        let outside = Coordinate(latitude: 36.5, longitude: -122.5)
        #expect(Self.square.distanceToBoundary(from: outside) > Self.square
            .distanceToBoundary(from: inside))
    }

    @Test func distanceToBoundary_tooFewVertices_returnsInfinity() {
        let empty = GeoPolygon(vertices: [])
        #expect(empty
            .distanceToBoundary(from: Coordinate(latitude: 37.5, longitude: -122.5)) == .infinity)
    }
}

struct RegionAttributorDistanceTests {
    let attributor = RegionAttributor.shared

    @Test func distanceToBoundary_otherRegion_returnsNil() {
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
        #expect(attributor.distanceToBoundary(of: .other, from: sf) == nil)
    }

    @Test func distanceToBoundary_insideRegion_isPositive() throws {
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
        let distance = attributor.distanceToBoundary(of: .california, from: sf)
        #expect(distance != nil)
        #expect(try #require(distance) > 0)
    }

    @Test func distanceToBoundary_outsideCalifornia_isPositive() throws {
        // Reno is outside California but relatively close to the border.
        let reno = Coordinate(latitude: 39.5296, longitude: -119.8138)
        let distance = attributor.distanceToBoundary(of: .california, from: reno)
        #expect(distance != nil)
        #expect(try #require(distance) > 0)
        // Should be on the order of tens of km, not hundreds.
        #expect(try #require(distance) < 200_000)
    }
}
