import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct PrivacyPassportCardSurfaceTests {
    @Test func hosts() throws {
        let rootView = PrivacyPassportCardSurface(tilt: .preview) {
            Color.clear.frame(height: 80)
        }
        .whereBroadwayRoot()
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
