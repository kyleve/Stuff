import Testing
@testable import WhereUI

struct WhereThemeComponentsCapabilitiesTests {
    @Test(arguments: [
        WhereThemeComponents.Role.locations,
        .elsewhere,
        .year,
        .settings,
        .sheet,
        .section,
    ])
    func nativeHostsRejectUnsupportedSurfaceAndHeading(role: WhereThemeComponents.Role) throws {
        var components = WhereThemeComponents()
        components[role] = .init()
        components[role]?.surface = .value(.init(rawValue: "paper"))
        #expect(throws: WhereThemeValidationError.self) { try components.validateCapabilities() }
        components[role]?.surface = .clear
        components[role]?.heading = .value(.init(rawValue: "heading"))
        #expect(throws: WhereThemeValidationError.self) { try components.validateCapabilities() }
        components[role]?.heading = .clear
        try components.validateCapabilities()
    }

    @Test func nativeArtworkCannotSilentlyDisappearOnTheWrongHost() throws {
        var components = WhereThemeComponents()
        components.privacy = .init()
        components.privacy?.nativeArtwork = [.regionPattern]
        #expect(throws: WhereThemeValidationError.self) { try components.validateCapabilities() }
        components.privacy?.nativeArtwork = [.stamp]
        try components.validateCapabilities()
        components.privacy?.nativeArtwork = []
        try components.validateCapabilities()
    }

    @Test(arguments: [WhereThemeComponents.Role.section, .timelineEntry])
    func nativeJoinedRowsRejectOverflow(role: WhereThemeComponents.Role) throws {
        var components = WhereThemeComponents()
        components[role] = .init()
        let theme = try WhereBundledThemeDefinitions.load("HalloweenTheme")
        components[role]?.artwork = theme.components.regularCard?.artwork
        #expect(throws: WhereThemeValidationError.self) { try components.validateCapabilities() }
        let interior = components[role]?.artwork?.filter { $0.placement.plane == .interior }
        components[role]?.artwork = interior
        try components.validateCapabilities()
    }
}
