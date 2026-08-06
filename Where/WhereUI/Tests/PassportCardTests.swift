import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct PassportCardTests {
    @Test func hostsInformationalContent() throws {
        let rootView = PassportCard(
            title: .settingsPrivacyTitle,
            detail: .settingsPrivacyDetail,
            sealSystemImage: "lock.shield.fill",
            accessorySystemImage: nil,
            isInteractive: false,
            surface: .reflective(tilt: .preview),
        )
        .whereBroadwayRoot()
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
