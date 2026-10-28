import Foundation
@testable import RegionKit
import Testing

/// Covers ``RegionURL`` (RegionKit's `region://` identity builder/parser) and
/// the `Region.regionURL` identity used for log `externalID` correlation.
struct RegionURLTests {
    @Test func buildsCollectionTypeAndSortedParams() {
        let url = RegionURL.url(
            collection: "regions",
            type: "us-CA",
            items: ["b": "2", "a": "1"],
        )
        #expect(url.absoluteString == "region://regions/us-CA?a=1&b=2")
    }

    @Test func buildsWithoutParamsWhenEmpty() {
        let url = RegionURL.url(collection: "regions", type: "canada", items: [:])
        #expect(url.absoluteString == "region://regions/canada")
    }

    @Test func parsesBackIntoParts() throws {
        let url = try #require(URL(string: "region://regions/us-NY?since=2026"))
        let parts = try #require(RegionURL.parts(of: url))
        #expect(parts.collection == "regions")
        #expect(parts.type == "us-NY")
        #expect(parts.value("since") == "2026")
    }

    @Test func rejectsForeignSchemes() throws {
        // A store:// URL is a different namespace; RegionURL must not claim it.
        let url = try #require(URL(string: "store://issues/borderDrift?day=2026-04-01"))
        #expect(RegionURL.parts(of: url) == nil)
    }

    @Test func regionVendsItsCanonicalIdentity() {
        #expect(Region.california.regionURL.absoluteString == "region://regions/us-CA")
        #expect(Region.other.regionURL.absoluteString == "region://regions/other")
    }
}
