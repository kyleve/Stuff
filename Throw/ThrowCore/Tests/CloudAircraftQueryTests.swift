import Testing
@testable import ThrowCore

struct CloudAircraftQueryTests {
    @Test func planDescriptionsRedactTransmittedCenter() throws {
        let coordinateSentinel = "44.123456"
        let plan = try CloudAircraftQueryPlan(
            coarseCenter: GeoCoordinate(latitude: 44.123456, longitude: -93.654321),
            transmittedRadius: NauticalMiles(value: 60),
        )

        #expect(String(describing: plan).contains(coordinateSentinel) == false)
        #expect(String(reflecting: plan).contains(coordinateSentinel) == false)
    }

    @Test func snapsCenterAndAddsTenMilePadding() throws {
        let query = try AircraftQuery(
            observer: ThrowCoreFixture.observer(latitude: 37.04, longitude: -122.06),
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            includeGroundAircraft: false,
        )
        let plan = try CloudAircraftQuery.plan(for: query)
        #expect(plan.coarseCenter.latitude == 37)
        #expect(plan.coarseCenter.longitude == -122.1)
        #expect(plan.transmittedRadius.value == 60)
    }

    @Test func capsPaddedMapQueryAtProviderMaximum() throws {
        let plan = try CloudAircraftQuery.plan(for: ThrowCoreFixture.mapQuery(radius: 240))
        #expect(plan.transmittedRadius.value == 250)
    }

    @Test func trueSkyAlwaysQueriesProviderMaximum() throws {
        let plan = try CloudAircraftQuery.plan(for: ThrowCoreFixture.skyQuery(minimumElevation: 45))
        #expect(plan.transmittedRadius.value == 250)
    }

    @Test func postFilterUsesExactObserverAndUnpaddedMapRadius() throws {
        let near = try ThrowCoreFixture.observation(latitude: 37.01)
        let outside = try ThrowCoreFixture.observation(latitude: 37.2)
        let filtered = try CloudAircraftQuery.postFilter(
            [near, outside],
            for: ThrowCoreFixture.mapQuery(radius: 5),
        )
        #expect(filtered.count == 1)
        #expect(filtered.first?.coordinate == near.coordinate)
    }

    @Test func altitudeLessAircraftRemainEligibleForMap() throws {
        let observation = try ThrowCoreFixture.observation(altitudeFeet: nil)
        let filtered = try CloudAircraftQuery.postFilter(
            [observation],
            for: ThrowCoreFixture.mapQuery(),
        )
        #expect(filtered.count == 1)
    }

    @Test func trueSkyOmitsGroundEvenWhenProviderSuppliesGeometricAltitude() throws {
        let ground = try ThrowCoreFixture.observation(
            latitude: 37,
            longitude: -122,
            altitudeFeet: 100,
            state: .ground,
        )
        let filtered = try CloudAircraftQuery.postFilter(
            [ground],
            for: ThrowCoreFixture.skyQuery(),
        )
        #expect(filtered.isEmpty)
    }

    @Test func distantGlobalRecordIsExcludedWithoutThrowing() throws {
        let distant = try ThrowCoreFixture.observation(latitude: -37, longitude: 58)
        let filtered = try CloudAircraftQuery.postFilter(
            [distant],
            for: ThrowCoreFixture.mapQuery(radius: 240),
        )
        #expect(filtered.isEmpty)
    }
}
