import Testing
@testable import ThrowCore

struct LayerCatalogTests {
    @Test func catalogEnablesAirAndTransitLayers() {
        let catalog = LayerCatalog.standard
        #expect(
            catalog.descriptors.map(\.id) == [
                .flights,
                .geography,
                .stars,
                .satellites,
                .transitNetwork,
                .transitVehicles,
            ],
        )
        #expect(catalog.descriptors.first?.supportedModes == [.map, .trueSky])
        #expect(catalog.descriptors[0].runtimeFactory() is FlightsLayerRuntime)
        #expect(catalog.descriptors[1].supportedModes == [.map])
        #expect(catalog.descriptors[1].runtimeFactory() is GeographyLayerRuntime)
        #expect(catalog.geography.zOrder < catalog.flights.zOrder)
        #expect(catalog.geography.zOrder == GeographyLayerKind.zOrder)
        #expect(catalog.flights.zOrder == FlightsLayerKind.zOrder)
        guard case .enabled = catalog.descriptors[0].availability else {
            Issue.record("Flights should be enabled")
            return
        }
        guard case .enabled = catalog.descriptors[1].availability else {
            Issue.record("Geography should be enabled")
            return
        }
        guard case .planned = catalog.descriptors[2].availability else {
            Issue.record("Stars should be planned")
            return
        }
        guard case .enabled = catalog.descriptors[4].availability,
              case .enabled = catalog.descriptors[5].availability
        else {
            Issue.record("Transit layers should be enabled")
            return
        }
    }
}
