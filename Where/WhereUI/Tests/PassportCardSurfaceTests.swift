import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct PassportCardSurfaceTests {
    @Test func hostsSecurityPrintAndReflectiveSurfaces() throws {
        let shape = RoundedRectangle(
            cornerRadius: WhereStylesheet.default.passportCard.cornerRadius,
        )
        let rootView = VStack {
            PassportCardSurface(tilt: nil, isInteractive: true, shape: shape) {
                Color.clear.frame(height: 80)
            }
            PassportCardSurface(tilt: .preview, isInteractive: false, shape: shape) {
                Color.clear.frame(height: 80)
            }
        }
        .whereBroadwayRoot()
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
