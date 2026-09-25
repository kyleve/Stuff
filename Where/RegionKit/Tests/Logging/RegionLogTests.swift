import PeriscopeCore
@testable import RegionKit
import Testing

/// Covers RegionKit's Periscope log tree: the scope names/hierarchy the
/// ``RegionLog`` facade vends, and each collaborator event's rendering.
struct RegionLogTests {
    // MARK: - Scope tree

    @Test func rootScopeIsRegionKit() {
        #expect(RegionLog.root.primaryScope.name == "RegionKit")
    }

    @Test func collaboratorScopesDescendFromTheRoot() {
        let rootID = RegionLog.root.primaryScope.id
        #expect(RegionLog.attributor.primaryScope.name == "RegionAttributor")
        #expect(RegionLog.attributor.primaryScope.parentID == rootID)
        #expect(RegionLog.catalog.primaryScope.name == "RegionCatalog")
        #expect(RegionLog.catalog.primaryScope.parentID == rootID)
        #expect(RegionLog.geometryCatalog.primaryScope.name == "RegionGeometryCatalog")
        #expect(RegionLog.geometryCatalog.primaryScope.parentID == rootID)
    }

    // MARK: - RegionCatalogLog

    @Test func catalogEventsRenderAndLevel() {
        #expect(RegionCatalogLog.MissingManifest().level == .fault)
        #expect(RegionCatalogLog.DecodeFailed(
            description: .restricted(.errorDetails, "boom"),
        ).level == .fault)
        #expect(RegionCatalogLog.Loaded(regionCount: .shared(.count, 4)).level == .info)
        #expect(RegionCatalogLog.Loaded(
            regionCount: .shared(.count, 4),
        ).message.contains("4 region"))
    }

    // MARK: - RegionAttributorLog

    @Test func attributorEventsCarryRegionAsExternalID() {
        // The region rides on externalID as its region:// identity (see
        // RegionURLTests for the exact string).
        #expect(
            RegionAttributorLog.MissingGeometry(region: .restricted(.location, .california))
                .externalID == Region.california.regionURL.absoluteString,
        )
        #expect(
            RegionAttributorLog.EmptyPolygons(region: .restricted(.location, .canada))
                .externalID == Region.canada.regionURL.absoluteString,
        )
        #expect(
            RegionAttributorLog.DecodeFailed(
                region: .restricted(.location, .newYork),
                description: .restricted(.errorDetails, "x"),
            )
            .externalID == Region.newYork.regionURL.absoluteString,
        )
        #expect(RegionAttributorLog.Loaded(
            regionCount: .shared(.count, 2),
        ).externalID == nil)
    }

    @Test func attributorFaultsAndInfo() {
        #expect(RegionAttributorLog.MissingGeometry(
            region: .restricted(.location, .california),
        ).level == .fault)
        #expect(RegionAttributorLog.EmptyPolygons(
            region: .restricted(.location, .california),
        ).level == .fault)
        #expect(
            RegionAttributorLog.DecodeFailed(
                region: .restricted(.location, .california),
                description: .restricted(.errorDetails, "x"),
            ).level == .fault,
        )
        #expect(RegionAttributorLog.Loaded(
            regionCount: .shared(.count, 2),
        ).level == .info)
    }

    // MARK: - RegionGeometryCatalogLog

    @Test func geometryCatalogFailureIsWarning() {
        let event = RegionGeometryCatalogLog.LoadFailed(
            kind: .restricted(.technicalState, "source"),
            description: .restricted(.errorDetails, "nope"),
        )
        #expect(event.level == .warning)
        #expect(event.message.contains("source"))
    }

    // MARK: - Span names

    @Test func perRegionLoadSpansAreNamedAfterTheRegionNotItsSwiftShape() {
        // Reflection would render this `loadRegion(RegionKit.Region(rawValue:
        // "us-CA"))`, pinning a Swift-internal spelling into recorded history and
        // into the name the span tools group timings by.
        #expect(
            String(describing: RegionAttributorLog.SpanName.loadRegion(.california))
                == "loadRegion(us-CA)",
        )
        #expect(String(describing: RegionAttributorLog.SpanName.loadPolygons) == "loadPolygons")
    }
}
