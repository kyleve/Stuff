import Foundation
import Testing
@testable import ThrowCore

enum TransitFixture {
    static let agencyID = TransitAgencyID.mtaNewYorkCityTransit

    static func routeID(_ value: String = "A") throws -> TransitRouteID {
        try #require(TransitRouteID(agencyID: agencyID, rawValue: value))
    }

    static func stopID(_ value: String) throws -> TransitStopID {
        try #require(TransitStopID(agencyID: agencyID, rawValue: value))
    }

    static func tripID(_ value: String = "trip-A") throws -> TransitTripID {
        try #require(TransitTripID(agencyID: agencyID, rawValue: value))
    }

    static func color() throws -> TransitColor {
        try #require(TransitColor(hex: "0039A6"))
    }

    static func schedule(fetchedAt: Date = ThrowCoreFixture.date) throws -> TransitSchedule {
        let routeID = try routeID()
        let firstID = try stopID("A01N")
        let secondID = try stopID("A02N")
        let first = try TransitStop(
            id: firstID,
            name: "First",
            coordinate: GeoCoordinate(latitude: 40.70, longitude: -74.01),
        )
        let second = try TransitStop(
            id: secondID,
            name: "Second",
            coordinate: GeoCoordinate(latitude: 40.72, longitude: -73.99),
        )
        return try TransitSchedule(
            agencyID: agencyID,
            revision: "fixture-1",
            fetchedAt: fetchedAt,
            routes: [routeID: TransitRoute(
                id: routeID,
                shortName: "A",
                color: color(),
            )],
            stops: [firstID: first, secondID: second],
            tripPatterns: [TransitTripPattern(
                tripID: tripID(),
                routeID: routeID,
                direction: 0,
                headsign: "Second",
                shapeID: "shape-A",
                stops: [
                    TransitTripPattern.Stop(
                        stopID: firstID,
                        sequence: 1,
                        arrivalSeconds: 0,
                        departureSeconds: 0,
                        shapeDistanceTraveled: 0,
                    ),
                    TransitTripPattern.Stop(
                        stopID: secondID,
                        sequence: 2,
                        arrivalSeconds: 120,
                        departureSeconds: 120,
                        shapeDistanceTraveled: 2,
                    ),
                ],
            )],
            shapes: [
                "shape-A": [
                    TransitShapePoint(coordinate: first.coordinate, distanceTraveled: 0),
                    TransitShapePoint(
                        coordinate: GeoCoordinate(latitude: 40.71, longitude: -74.00),
                        distanceTraveled: 1,
                    ),
                    TransitShapePoint(coordinate: second.coordinate, distanceTraveled: 2),
                ],
            ],
        )
    }

    static func snapshot(
        fetchedAt: Date = ThrowCoreFixture.date,
        nextStopRawValue: String = "A02N",
    ) throws
        -> TransitPartitionSnapshot
    {
        let partition = try #require(TransitFeedPartitionID(rawValue: "ace"))
        let runID = try #require(TransitRunID(
            agencyID: agencyID,
            partitionID: partition,
            serviceDate: "20231114",
            stableRunValue: "A-101",
        ))
        return try TransitPartitionSnapshot(
            partitionID: partition,
            generatedAt: fetchedAt,
            fetchedAt: fetchedAt,
            runs: [TransitRunObservation(
                id: runID,
                tripID: tripID(),
                routeID: routeID(),
                direction: 0,
                observedAt: fetchedAt,
                upcomingStops: [TransitStopTimePrediction(
                    stopID: stopID(nextStopRawValue),
                    arrival: fetchedAt.addingTimeInterval(60),
                    departure: fetchedAt.addingTimeInterval(60),
                )],
            )],
        )
    }
}
