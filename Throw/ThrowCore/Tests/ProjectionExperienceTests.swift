import Testing
@testable import ThrowCore

struct ProjectionExperienceTests {
    @Test func standardCatalogExposesBothProductionRuntimes() {
        let runnableIDs = ProjectionExperienceCatalog.standard.descriptors
            .compactMap(\.availability.runnableExperienceID)

        #expect(runnableIDs == [.airAndSpace, .transit])
    }

    @Test func standardCatalogDefinesRunnableAirAndSpaceAndTransit() throws {
        let catalog = ProjectionExperienceCatalog.standard

        #expect(catalog.descriptors.map(\.id) == [.airAndSpace, .transit])
        let airAndSpace = try #require(catalog[.airAndSpace])
        #expect(airAndSpace.availability == .runnable(.airAndSpace))
        #expect(airAndSpace.supportedModes == [.map, .trueSky])
        #expect(airAndSpace.layerIDs == [.geography, .flights, .stars, .satellites])
        #expect(airAndSpace.visibleContentKind == .aircraft)

        let transit = try #require(catalog[.transit])
        #expect(transit.availability == .runnable(.transit))
        #expect(transit.supportedModes == [.map])
        #expect(transit.layerIDs == [.geography, .transitNetwork, .transitVehicles])
        #expect(transit.visibleContentKind == .vehicles)
        #expect(Set(airAndSpace.layerIDs).contains(.geography))
        #expect(Set(transit.layerIDs).contains(.geography))
        #expect(catalog.runnableExperienceID(for: .airAndSpace) == .airAndSpace)
        #expect(catalog.runnableExperienceID(for: .transit) == .transit)
    }
}
