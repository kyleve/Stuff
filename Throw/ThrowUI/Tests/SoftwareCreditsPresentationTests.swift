import CreditKit
import Foundation
import Testing
@testable import ThrowUI

struct SoftwareCreditsPresentationTests {
    @Test func keepsLibrariesAndDevelopmentToolsDistinct() {
        let presentation = SoftwareCreditsPresentation(
            state: .loaded([
                credit(name: "Library", kind: .library),
                credit(name: "Tool", kind: .developmentTool),
            ]),
        )

        guard case let .loaded(credits) = presentation else {
            Issue.record("A loaded report must produce loaded credits")
            return
        }

        #expect(credits.libraries.map(\.name) == ["Library"])
        #expect(credits.developmentTools.map(\.name) == ["Tool"])
    }

    @Test func loadedEmptyReportStaysLoaded() {
        let presentation = SoftwareCreditsPresentation(state: .loaded([]))

        guard case let .loaded(credits) = presentation else {
            Issue.record("An empty report must remain a loaded report")
            return
        }

        #expect(credits.libraries.isEmpty)
        #expect(credits.developmentTools.isEmpty)
    }

    @Test func failedReportBecomesUnavailable() {
        let presentation = SoftwareCreditsPresentation(state: .failed)

        #expect(presentation == .unavailable)
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
