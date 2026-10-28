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

    @Test func distanceToSelfIsZero() {
        let point = Coordinate(latitude: 40.7128, longitude: -74.0060)
        #expect(point.distance(to: point) == 0)
    }

    @Test func distanceIsSymmetric() {
        let jfk = Coordinate(latitude: 40.6413, longitude: -73.7781)
        let sfo = Coordinate(latitude: 37.6213, longitude: -122.3790)
        #expect(abs(jfk.distance(to: sfo) - sfo.distance(to: jfk)) < 0.001)
    }

    /// One degree of latitude is ~111 km anywhere on the globe; a good
    /// low-distance sanity check that the haversine math is in meters.
    @Test func oneDegreeOfLatitudeIsAboutOneEleventhOfAThousandKm() {
        let start = Coordinate(latitude: 0, longitude: 0)
        let north = Coordinate(latitude: 1, longitude: 0)
        #expect(abs(start.distance(to: north) - 111_195) < 500)
    }

    /// The NYC→SF great-circle distance is ~4 150 km; the detector relies on
    /// this continent-spanning accuracy to read a cross-country flight's speed.
    @Test func transcontinentalDistanceIsAboutFourThousandKm() {
        let jfk = Coordinate(latitude: 40.6413, longitude: -73.7781)
        let sfo = Coordinate(latitude: 37.6213, longitude: -122.3790)
        let kilometers = jfk.distance(to: sfo) / 1000
        #expect(kilometers > 4100 && kilometers < 4200)
    }
}
