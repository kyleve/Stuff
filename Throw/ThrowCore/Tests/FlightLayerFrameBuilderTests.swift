import Testing
@testable import ThrowCore

struct FlightLayerFrameBuilderTests {
    @Test func providerRouteOverridesCallsignEnrichmentForMatchingAircraft() throws {
        let observation = try ThrowCoreFixture.observation(callsign: "UAL817")
        let providerRoute = try FlightRoute(
            origin: #require(AirportCode(rawValue: "SFO")),
            destination: #require(AirportCode(rawValue: "MEX")),
        )
        let staleRoute = try FlightRoute(
            origin: #require(AirportCode(rawValue: "DEL")),
            destination: #require(AirportCode(rawValue: "EWR")),
        )
        let frame = try builder.frame(
            observations: [resolved(observation)],
            observedAt: ThrowCoreFixture.date,
            providerRouteResults: [observation.id: .route(providerRoute)],
            observer: ThrowCoreFixture.observer(),
            labelMode: .adaptive,
            routeResults: [#require(FlightCallsign(rawValue: "UAL817")): .route(staleRoute)],
            availability: .current,
        )
        let mark = try #require(frame.marks.first { $0.id == .aircraft(observation.id) })
        #expect(mark.label?.primary == "SFO→MEX")
        #expect(mark.label?.secondary == "UAL817")
    }

    @Test func sourceConfirmedRouteMissMakesAircraftSecondaryWithoutEnrichment() throws {
        let observation = try ThrowCoreFixture.observation(
            source: .flightradar24,
            callsign: "THROW1",
        )
        let frame = try builder.frame(
            observations: [resolved(observation)],
            observedAt: ThrowCoreFixture.date,
            providerRouteResults: [observation.id: .unavailable],
            observer: ThrowCoreFixture.observer(),
            labelMode: .adaptive,
            routeResults: [:],
            availability: .current,
        )

        #expect(frame.marks.first?.prominence == .secondary)
        #expect(frame.marks.first?.label?.primary == "THROW1")
    }

    @Test func adaptiveLabelUsesCallsignWhileRouteIsUnavailable() throws {
        let observer = try ThrowCoreFixture.observer()
        let observation = try ThrowCoreFixture.observation(
            latitude: 37.01,
            longitude: -122,
            altitudeFeet: 1234,
        )
        let frame = try builder.frame(
            observations: [resolved(observation)],
            observedAt: ThrowCoreFixture.date,
            providerRouteResults: [:],
            observer: observer,
            labelMode: .adaptive,
            routeResults: [:],
            availability: .current,
        )
        let label = try #require(frame.marks.first?.label)
        #expect(label.primary == "THROW1")
        #expect(label.primaryRole == .detail)
        #expect(label.secondary == nil)
        #expect(frame.marks.first?.prominence == .primary)
        #expect(
            frame.marks.first?.glyph == .aircraft(AircraftGlyphDescriptor(
                family: .airliner,
                brand: nil,
                isGrounded: false,
                activity: .overflight,
            )),
        )
    }

    @Test func resolvedRouteLeadsWithAirportsAndSubordinatesCallsign() throws {
        let observation = try ThrowCoreFixture.observation(callsign: "UAL123")
        let routeCallsign = try #require(FlightCallsign(rawValue: "UAL123"))
        let route = try FlightRoute(
            origin: #require(AirportCode(rawValue: "JFK")),
            destination: #require(AirportCode(rawValue: "SFO")),
        )
        let frame = try builder.frame(
            observations: [resolved(observation)],
            observedAt: ThrowCoreFixture.date,
            providerRouteResults: [:],
            observer: ThrowCoreFixture.observer(),
            labelMode: .adaptive,
            routeResults: [routeCallsign: .route(route)],
            availability: .current,
        )

        let label = try #require(frame.marks.first?.label)
        #expect(label.primary == "JFK→SFO")
        #expect(label.primaryRole == .headline)
        #expect(label.secondary == "UAL123")
        #expect(frame.marks.first?.prominence == .primary)
    }

    @Test func completedRouteMissMakesAircraftSecondary() throws {
        let observation = try ThrowCoreFixture.observation(callsign: "THROW1")
        let callsign = try #require(FlightCallsign(rawValue: "THROW1"))
        let frame = try builder.frame(
            observations: [resolved(observation)],
            observedAt: ThrowCoreFixture.date,
            providerRouteResults: [:],
            observer: ThrowCoreFixture.observer(),
            labelMode: .adaptive,
            routeResults: [callsign: .unavailable],
            availability: .current,
        )

        #expect(frame.marks.first?.prominence == .secondary)
        #expect(frame.marks.first?.label?.primary == "THROW1")
    }

    @Test func completedRouteMissMakesMarksOnlyAircraftSecondary() throws {
        let observation = try ThrowCoreFixture.observation(callsign: "THROW1")
        let callsign = try #require(FlightCallsign(rawValue: "THROW1"))
        let frame = try builder.frame(
            observations: [resolved(observation)],
            observedAt: ThrowCoreFixture.date,
            providerRouteResults: [:],
            observer: ThrowCoreFixture.observer(),
            labelMode: .marksOnly,
            routeResults: [callsign: .unavailable],
            availability: .current,
        )

        #expect(frame.marks.first?.prominence == .secondary)
        #expect(frame.marks.first?.label == nil)
    }

    @Test func callsignModeNeverFallsBackToHexIdentity() throws {
        let observation = try ThrowCoreFixture.observation(callsign: nil)
        let frame = try builder.frame(
            observations: [resolved(observation)],
            observedAt: ThrowCoreFixture.date,
            providerRouteResults: [:],
            observer: ThrowCoreFixture.observer(),
            labelMode: .callsigns,
            routeResults: [:],
            availability: .current,
        )
        #expect(frame.marks.first?.label == nil)
        #expect(frame.marks.first?.prominence == .secondary)
    }

    private var builder: FlightLayerFrameBuilder {
        FlightLayerFrameBuilder(
            visualClassifier: AircraftVisualClassifier(catalog: .bundled),
            activityClassifier: FlightActivityClassifier(
                airportCatalog: AirportCatalog(airports: []),
            ),
        )
    }

    private func resolved(_ observation: AircraftObservation) -> ResolvedAircraftObservation {
        ResolvedAircraftObservation(
            observation: observation,
            motion: .reported(by: observation),
        )
    }
}
