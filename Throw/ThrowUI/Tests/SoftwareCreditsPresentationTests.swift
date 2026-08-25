import CreditKit
import Foundation
import Testing
@testable import ThrowUI

struct SoftwareCreditsPresentationTests {
    @Test func keepsLibrariesAndDevelopmentToolsDistinct() {
        let presentation = SoftwareCreditsPresentation(credits: [
            credit(name: "Library", kind: .library),
            credit(name: "Tool", kind: .developmentTool),
        ])

        #expect(presentation.libraries.map(\.name) == ["Library"])
        #expect(presentation.developmentTools.map(\.name) == ["Tool"])
    }

    private func credit(name: String, kind: SoftwareCredit.Kind) -> SoftwareCredit {
        SoftwareCredit(
            name: name,
            kind: kind,
            version: "1.0",
            homepageURL: URL(string: "https://example.com"),
            license: LicenseNotice(name: "MIT", text: "Fixture notice"),
        )
    }
}
