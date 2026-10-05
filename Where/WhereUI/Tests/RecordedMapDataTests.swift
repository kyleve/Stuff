import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

struct RecordedMapDataTests {
    @Test func denseMapKeepsBothEndsWithinRenderingLimits() throws {
        let coordinates = (0 ..< 10000).map {
            Coordinate(latitude: 35 + Double($0) / 10000, longitude: -120 + Double($0) / 1000)
        }
        let data = RecordedMapData(
            points: coordinates.map { RecordedMapPoint(
                coordinate: $0,
                horizontalAccuracy: 10,
                region: .other,
            ) },
            routes: [.init(id: .legacy, coordinates: coordinates)],
        )
        #expect(data.pins.count == RecordedMapData.maximumPins)
        #expect(data.pins.first?.point.coordinate == coordinates.first)
        let lastPin = try #require(data.pins.last)
        let arrival = try #require(coordinates.last)
        #expect(lastPin.point.coordinate.distance(to: arrival) < 1000)
        #expect(data.routes.first?.coordinates.count == RecordedMapData.maximumRoutePoints)
        #expect(data.routes.first?.coordinates.first == coordinates.first)
        #expect(data.routes.first?.coordinates.last == coordinates.last)
    }

    @Test func captureProjectionKeepsDatelineCrossingLocal() {
        let coordinates = [
            Coordinate(latitude: 20, longitude: 179),
            Coordinate(latitude: 20, longitude: -179),
        ]
        let data = RecordedMapData(
            points: [],
            routes: [.init(id: .legacy, coordinates: coordinates)],
        )
        #expect(data.captureBounds.width < 2_000_000)
        #expect(data.captureBounds.width > 0)
    }
}
