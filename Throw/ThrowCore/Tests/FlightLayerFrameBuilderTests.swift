import Testing
@testable import ThrowCore

struct FlightLayerFrameBuilderTests {
    @Test func adaptiveLabelUsesCallsignAndNearbyRoundedAltitude() throws {
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
        )
        let label = try #require(frame.marks.first?.label)
        #expect(label.primary == "THROW1")
        #expect(label.secondary == "1,200 ft")
        #expect(
            frame.marks.first?.glyph == .aircraft(AircraftGlyphDescriptor(
                family: .airliner,
                brand: nil,
                isGrounded: false,
            )),
        )
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
        )
        #expect(frame.marks.first?.label == nil)
    }

    private var builder: FlightLayerFrameBuilder {
        FlightLayerFrameBuilder(
            visualClassifier: AircraftVisualClassifier(catalog: .bundled),
        )
    }
}
