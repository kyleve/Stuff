import Testing
@testable import ThrowCore

struct FlightsLayerRuntimeTests {
    @Test func typedRuntimeProducesTheFlightsSemanticFrame() async throws {
        let observation = try ThrowCoreFixture.observation()
        let snapshot = AircraftSnapshot(
            source: .adsbLol,
            fetchedAt: ThrowCoreFixture.date,
            observations: [observation],
        )

        let frame = try await LayerCatalog.standard.flights.runtimeFactory().frame(
            for: FlightsLayerInput(
                snapshot: snapshot,
                observer: ThrowCoreFixture.observer(),
                labelMode: .callsigns,
                routeResults: [:],
                availability: .current,
            ),
        )

        #expect(frame.layerID == .flights)
        #expect(frame.marks.first?.label?.primary == "THROW1")
    }
}
