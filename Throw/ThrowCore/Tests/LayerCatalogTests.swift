import Testing
@testable import ThrowCore

struct LayerCatalogTests {
    @Test func v1CatalogEnablesFlightsAndMapOnlyGeography() {
        let catalog = LayerCatalog.standard
        #expect(catalog.descriptors.map(\.id) == [.flights, .geography, .stars, .satellites])
        #expect(catalog.descriptors.first?.supportedModes == [.map, .trueSky])
        #expect(catalog.descriptors[0].runtimeFactory() is FlightsLayerRuntime)
        #expect(catalog.descriptors[1].supportedModes == [.map])
        #expect(catalog.descriptors[1].runtimeFactory() is GeographyLayerRuntime)
        #expect(catalog.geography.zOrder < catalog.flights.zOrder)
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
    }
}
