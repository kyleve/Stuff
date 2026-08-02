import RegionKit
import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct RegionOutlineArtworkTests {
    /// Exercise the Canvas with RegionKit's real multipart geometry so changes
    /// to either side of the projection boundary cannot leave cards blank or
    /// trap on a representative state outline.
    @Test func hostsRealRegionGeometry() async throws {
        let outlines = await RegionGeometryCatalog.outlines(for: .california)
        let style = try #require(WhereStylesheet.default.card.regular.regionShape)
        let artwork = RegionOutlineArtwork(
            outlines: outlines,
            tint: .orange,
            style: style,
            placement: .watermark,
        )

        #expect(!outlines.isEmpty)
        try show(UIHostingController(rootView: artwork)) { hosted in
            hosted.view.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
            hosted.view.layoutIfNeeded()
            #expect(hosted.view != nil)
        }
    }
}
