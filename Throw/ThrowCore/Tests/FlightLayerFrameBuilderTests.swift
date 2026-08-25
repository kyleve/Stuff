import Testing
@testable import ThrowCore

struct FlightLayerFrameBuilderTests {
    @Test func adaptiveLabelUsesCallsignWhileRouteIsUnavailable() throws {
        let observer = try ThrowCoreFixture.observer()
        let observation = try ThrowCoreFixture.observation(
            latitude: 37.01,
            longitude: -122,
            altitudeFeet: 1234,
        )
        let snapshot = AircraftSnapshot(
            source: .adsbLol,
            fetchedAt: ThrowCoreFixture.date,
            observations: [observation],
        )
        let frame = try builder.frame(
            snapshot: snapshot,
            observer: observer,
            labelMode: .adaptive,
            routes: [:],
        )
        let label = try #require(frame.marks.first?.label)
        #expect(label.primary == "THROW1")
        #expect(label.secondary == nil)
        #expect(
            frame.marks.first?.glyph == .aircraft(AircraftGlyphDescriptor(
                family: .airliner,
                brand: nil,
                isGrounded: false,
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
            snapshot: AircraftSnapshot(
                source: .adsbLol,
                fetchedAt: ThrowCoreFixture.date,
                observations: [observation],
            ),
            observer: ThrowCoreFixture.observer(),
            labelMode: .adaptive,
            routes: [routeCallsign: route],
        )

        let label = try #require(frame.marks.first?.label)
        #expect(label.primary == "JFK → SFO")
        #expect(label.secondary == "UAL123")
    }

    @Test func callsignModeNeverFallsBackToHexIdentity() throws {
        let observation = try ThrowCoreFixture.observation(callsign: nil)
        let frame = try builder.frame(
            snapshot: AircraftSnapshot(
                source: .adsbLol,
                fetchedAt: ThrowCoreFixture.date,
                observations: [observation],
            ),
            observer: ThrowCoreFixture.observer(),
            labelMode: .callsigns,
            routes: [:],
        )
        #expect(frame.marks.first?.label == nil)
    }

    private var builder: FlightLayerFrameBuilder {
        FlightLayerFrameBuilder(
            visualClassifier: AircraftVisualClassifier(catalog: .bundled),
        )
    }
}
