import Testing
@testable import ThrowCore

struct TransitLayerRuntimesTests {
    @Test func typedRuntimesCannotAcceptTheOtherLayersInput() async throws {
        let builder = TransitLayerFrameBuilder()
        let network = TransitNetworkLayerRuntime(builder: builder)
        let vehicles = TransitVehiclesLayerRuntime(builder: builder)
        let networkFrame = try await network.frame(for: TransitFixture.schedule())
        let vehiclesFrame = try await vehicles.frame(for: TransitVehiclesLayerInput(
            estimates: [],
            labelMode: .routeOnly,
            fetchedAt: ThrowCoreFixture.date,
            availability: .current,
        ))
        #expect(networkFrame.layerID == .transitNetwork)
        #expect(vehiclesFrame.layerID == .transitVehicles)
    }
}
