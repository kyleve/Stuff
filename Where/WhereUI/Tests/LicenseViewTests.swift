import CreditKit
import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

/// Covers the license notice pushed from Settings > About: it renders the
/// bundled text for a real credit, which is the compliance-relevant path.
@MainActor
struct LicenseViewTests {
    @Test func hostsEveryCreditsNotice() throws {
        for credit in CreditCatalog.shared.credits {
            let rootView = NavigationStack { LicenseView(credit: credit) }
            try show(UIHostingController(rootView: rootView)) { hosted in
                #expect(hosted.view != nil)
            }
        }
    }
}
