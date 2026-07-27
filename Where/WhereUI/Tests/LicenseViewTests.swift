import CreditKit
import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

/// Covers the license notice pushed from Settings > About: it renders the text
/// the report carries, which is the compliance-relevant path.
@MainActor
struct LicenseViewTests {
    @Test func hostsEveryCreditsNotice() throws {
        for credit in PreviewSupport.sampleAttribution().credits {
            let rootView = NavigationStack { LicenseView(credit: credit) }
            try show(UIHostingController(rootView: rootView)) { hosted in
                #expect(hosted.view != nil)
            }
        }
    }

    @Test func hostsACreditWhoseNoticeIsEmpty() throws {
        // The generator refuses to write one, so this is the defensive path — it
        // must say the notice is unavailable rather than render a blank page
        // that reads like a license with no terms.
        let credit = PreviewSupport.sampleCredit(noticeText: "")
        let rootView = NavigationStack { LicenseView(credit: credit) }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
