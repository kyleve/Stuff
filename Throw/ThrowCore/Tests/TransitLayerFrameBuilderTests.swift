import Testing
@testable import ThrowCore

struct TransitLayerFrameBuilderTests {
    @Test func networkDeduplicatesSharedRouteShapes() throws {
        let frame = try TransitLayerFrameBuilder().networkFrame(
            schedule: TransitFixture.schedule(),
        )
        #expect(frame.lines.count == 1)
        let style = frame.lines[0].style
        #expect(style.routeID.rawValue == "A")
    }

    @Test func routeOnlyUsesColoredTrainDotWithoutStationMarks() throws {
        var estimator = TransitPositionEstimator()
        let estimates = try estimator.estimates(
            snapshots: [TransitFixture.snapshot()],
            schedule: TransitFixture.schedule(),
            at: ThrowCoreFixture.date,
        )
        let frame = TransitLayerFrameBuilder().vehiclesFrame(
            estimates: estimates,
            labelMode: .routeOnly,
            fetchedAt: ThrowCoreFixture.date,
            availability: .current,
        )
        #expect(frame.marks.count == 1)
        let mark = try #require(frame.marks.first)
        #expect(mark.label == nil)
        #expect(mark.transitMotion != nil)
        guard case .vehicle = mark.element else {
            Issue.record("Expected a typed transit vehicle mark")
            return
        }
    }

    @Test func vehicleIdentityKeepsOtherwiseEqualRunsFromDifferentAgencies() throws {
        let secondAgency = try #require(TransitAgencyID(rawValue: "second-agency"))
        let estimates = try [TransitFixture.agencyID, secondAgency].map { agencyID in
            try estimate(agencyID: agencyID)
        }

        let frame = TransitLayerFrameBuilder().vehiclesFrame(
            estimates: estimates,
            labelMode: .routeOnly,
            fetchedAt: ThrowCoreFixture.date,
            availability: .current,
        )

        let vehicleIDs = frame.marks.compactMap { mark -> TransitVehicleID? in
            guard case let .vehicle(id, _) = mark.element else { return nil }
            return id
        }
        #expect(vehicleIDs.count == 2)
        #expect(Set(vehicleIDs).count == 2)
    }

    private func estimate(agencyID: TransitAgencyID) throws -> TransitVehicleEstimate {
        let partitionID = try #require(TransitFeedPartitionID(rawValue: "shared-partition"))
        let routeID = try #require(TransitRouteID(agencyID: agencyID, rawValue: "A"))
        let stopID = try #require(TransitStopID(agencyID: agencyID, rawValue: "A01"))
        let coordinate = try GeoCoordinate(latitude: 40.7, longitude: -74)
        let stop = TransitStop(
            id: stopID,
            name: "Stop",
            coordinate: coordinate,
        )
        return try TransitVehicleEstimate(
            run: TransitRunObservation(
                id: #require(TransitRunID(
                    agencyID: agencyID,
                    partitionID: partitionID,
                    serviceDate: "20231114",
                    stableRunValue: "A-101",
                )),
                tripID: nil,
                routeID: routeID,
                direction: 0,
                observedAt: ThrowCoreFixture.date,
                upcomingStops: [TransitStopTimePrediction(
                    stopID: stopID,
                    arrival: ThrowCoreFixture.date,
                    departure: ThrowCoreFixture.date,
                )],
            ),
            route: TransitRoute(
                id: routeID,
                shortName: "A",
                color: #require(TransitColor(hex: "0039A6")),
            ),
            coordinate: stop.coordinate,
            motion: nil,
            confidence: .feedTracked,
            destination: stop,
            nextStop: stop,
        )
    }
}
