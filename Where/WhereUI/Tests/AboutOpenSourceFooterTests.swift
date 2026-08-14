import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct AboutOpenSourceFooterTests {
    @Test func linksToTheCanonicalProjectRepository() {
        #expect(AboutOpenSourceFooter.projectURL
            .absoluteString == "https://github.com/kyleve/Stuff")
    }

    @Test func hosts() throws {
        let rootView = AboutOpenSourceFooter().whereBroadwayRoot()
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
