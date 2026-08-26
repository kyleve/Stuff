import Testing
@testable import ThrowCore

struct ProjectionExperienceTests {
    @Test func standardCatalogDefinesAirAndSpaceAndPlannedTransit() throws {
        let catalog = ProjectionExperienceCatalog.standard

        #expect(catalog.descriptors.map(\.id) == [.airAndSpace, .transit])
        let airAndSpace = try #require(catalog[.airAndSpace])
        #expect(airAndSpace.availability == .enabled)
        #expect(airAndSpace.supportedModes == [.map, .trueSky])
        #expect(airAndSpace.layerIDs == [.geography, .flights, .stars, .satellites])
        #expect(airAndSpace.visibleContentKind == .aircraft)

        let transit = try #require(catalog[.transit])
        #expect(transit.availability == .planned)
        #expect(transit.supportedModes == [.map])
        #expect(transit.layerIDs == [.geography, .transitNetwork, .transitVehicles])
        #expect(transit.visibleContentKind == .vehicles)
        #expect(Set(airAndSpace.layerIDs).contains(.geography))
        #expect(Set(transit.layerIDs).contains(.geography))
    }
}
