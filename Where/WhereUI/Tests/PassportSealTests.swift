import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct PassportSealTests {
    @Test func hosts() throws {
        let rootView = PassportSeal(systemSymbol: .lockShieldFill, tint: .accentColor)
            .whereBroadwayRoot()
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
