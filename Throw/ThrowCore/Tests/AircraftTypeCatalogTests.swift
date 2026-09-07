import Foundation
import Testing
@testable import ThrowCore

struct AircraftTypeCatalogTests {
    @Test func bundledCatalogContainsRepresentativeFamilies() throws {
        let catalog = AircraftTypeCatalog.bundled
        let airliner = try #require(AircraftTypeDesignator(rawValue: "B738"))
        let helicopter = try #require(AircraftTypeDesignator(rawValue: "A109"))

        #expect(catalog.characteristics(for: airliner)?.engineCode == "J")
        #expect(catalog.characteristics(for: airliner)?.wakeCategory == .medium)
        #expect(catalog.characteristics(for: helicopter)?.airframeCode == "H")
    }

    @Test func invalidArchivesFailClosed() {
        #expect(throws: AircraftTypeCatalogError.unsupportedVersion) {
            try AircraftTypeCatalog(data: Data("{\"version\":2,\"types\":{}}".utf8))
        }
        #expect(throws: AircraftTypeCatalogError.invalidRecord) {
            try AircraftTypeCatalog(
                data: Data("{\"version\":1,\"types\":{\"B738\":{\"d\":\"BA\",\"w\":\"M\"}}}".utf8),
            )
        }
    }
}
