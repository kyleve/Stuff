import Testing
@testable import ThrowCore

struct DomainValuesTests {
    @Test(arguments: [-720.0, -10.0, 0.0, 360.0, 725.0])
    func bearingNormalizesIntoOneTurn(input: Double) throws {
        let bearing = try Bearing(degrees: input)
        #expect((0 ..< 360).contains(bearing.degrees))
    }

    @Test func negativeBearingWrapsClockwise() throws {
        #expect(try Bearing(degrees: -10).degrees == 350)
    }

    @Test(arguments: [-90.0, 0.0, 90.0])
    func coordinateAcceptsLatitudeBoundary(latitude: Double) throws {
        #expect(try GeoCoordinate(latitude: latitude, longitude: 0).latitude == latitude)
    }

    @Test(arguments: [-90.1, 90.1])
    func coordinateRejectsLatitudeOutsideGlobe(latitude: Double) {
        #expect(throws: ThrowValidationError.self) {
            try GeoCoordinate(latitude: latitude, longitude: 0)
        }
    }

    @Test func observerDescriptionsRedactCoordinates() throws {
        let latitudeSentinel = "12.345678"
        let longitudeSentinel = "-98.765432"
        let coordinate = try GeoCoordinate(
            latitude: 12.345678,
            longitude: -98.765432,
        )
        let observer = try ObserverPosition(
            coordinate: coordinate,
            altitude: Altitude(feet: 4321),
        )
        let renderings = [
            String(describing: coordinate),
            String(reflecting: coordinate),
            String(describing: observer),
            String(reflecting: observer),
        ]

        for rendering in renderings {
            #expect(rendering.contains(latitudeSentinel) == false)
            #expect(rendering.contains(longitudeSentinel) == false)
        }
    }

    @Test(arguments: [5.0, 50.0, 240.0])
    func mapViewportAcceptsFiveMileSteps(radius: Double) throws {
        #expect(
            try MapViewport(radius: NauticalMiles(value: radius)).radius.value == radius,
        )
    }

    @Test(arguments: [4.0, 7.0, 245.0])
    func mapViewportRejectsInvalidSteps(radius: Double) throws {
        #expect(throws: ThrowValidationError.self) {
            try MapViewport(radius: NauticalMiles(value: radius))
        }
    }

    @Test(arguments: [5, 10, 300])
    func pollingIntervalAcceptsPublishedBounds(seconds: Int) throws {
        #expect(try PollingInterval(seconds: seconds).seconds == seconds)
    }

    @Test(arguments: [4, 301])
    func pollingIntervalRejectsOutOfRange(seconds: Int) {
        #expect(throws: ThrowValidationError.self) {
            try PollingInterval(seconds: seconds)
        }
    }
}
