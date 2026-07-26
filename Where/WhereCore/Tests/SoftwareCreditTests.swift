import Foundation
import Testing
@testable import WhereCore

/// The guard behind the About screen's open-source credits: every credited
/// library ships the license notice it's required to, and the list matches what
/// the app actually links.
struct SoftwareCreditTests {
    @Test func creditsEveryLinkedThirdPartyLibrary() {
        // ZIPFoundation (BackupService's archive reader/writer) is the app's only
        // external package — everything else in the graph is first-party. Update
        // this alongside the root Package.swift.
        #expect(SoftwareCredit.all.map(\.name) == ["ZIPFoundation"])
    }

    @Test func everyCreditShipsItsLicenseText() throws {
        for credit in SoftwareCredit.all {
            let text = try #require(
                credit.licenseText(),
                "\(credit.name) is credited but its license text isn't bundled",
            )
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @Test func theZIPFoundationNoticeCarriesItsCopyrightLine() throws {
        let credit = try #require(SoftwareCredit.all.first { $0.name == "ZIPFoundation" })
        let text = try #require(credit.licenseText())
        // MIT requires the copyright notice and permission notice verbatim, so a
        // truncated or placeholder file has to fail rather than merely look full.
        #expect(text.contains("MIT License"))
        #expect(text.contains("Copyright (c) 2017-2025 Thomas Zoechling"))
        #expect(text.contains("THE SOFTWARE IS PROVIDED \"AS IS\""))
        #expect(credit.licenseName == "MIT License")
        #expect(credit.version == "0.9.20")
    }

    @Test func everyCreditLinksItsProject() {
        for credit in SoftwareCredit.all {
            #expect(credit.homepageURL != nil)
        }
    }

    @Test func creditsAreUniquelyIdentified() {
        let ids = SoftwareCredit.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
