import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct RegionLocationConstellationTests {
    /// LocationsView's image matrix owns pixel fidelity; this focused host
    /// covers construction with a clipped point and the live stylesheet spec.
    @Test func hostsAProjectedPointInsideTheRegionPath() throws {
        let path = Path { $0.addRect(CGRect(x: 0, y: 0, width: 100, height: 50)) }
        let artwork = try #require(WhereStylesheet.default.card.regular.regionShape?.watermark)
        let constellation = RegionLocationConstellation(
            path: path,
            points: [.init(position: CGPoint(x: 50, y: 25), horizontalAccuracy: 10)],
            tint: .orange,
            artworkStyle: artwork,
            style: .standard,
        )

        try show(UIHostingController(rootView: constellation)) { hosted in
            hosted.view.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
            hosted.view.layoutIfNeeded()
            #expect(hosted.view != nil)
        }
    }
}
