import Testing
@testable import ThrowCore

struct LayerCatalogTests {
    @Test func v1CatalogEnablesOnlyFlightsAndDeclaresModes() {
        let catalog = LayerCatalog.standard
        #expect(catalog.descriptors.map(\.id) == [.flights, .stars, .satellites])
        #expect(catalog.descriptors.first?.supportedModes == [.map, .trueSky])
        #expect(catalog.descriptors[0].runtimeFactory() is FlightsLayerRuntime)
        guard case .enabled = catalog.descriptors[0].availability else {
            Issue.record("Flights should be enabled")
            return
        }
        guard case .planned = catalog.descriptors[1].availability else {
            Issue.record("Stars should be planned")
            return
        }
    }
}
