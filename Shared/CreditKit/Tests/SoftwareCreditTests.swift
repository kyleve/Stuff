@_spi(Testing) import CreditKit
import Foundation
import Testing

struct SoftwareCreditTests {
    // These iterate rather than taking `arguments:`: a parameterized case list
    // is evaluated when the test is discovered, which is before `Bundle.module`
    // resolves the manifest — the suite would silently register zero cases and
    // report as passing without checking anything.

    @Test("every credit ships a non-empty license notice")
    func everyCreditShipsALicenseNotice() {
        for credit in CreditCatalog.shared.credits {
            let text = credit.licenseText()
            #expect(text?.isEmpty == false, "\(credit.name) has no vendored license text")
        }
    }

    @Test("every credit names its license, version, and home")
    func everyCreditNamesItsLicenseVersionAndHome() {
        for credit in CreditCatalog.shared.credits {
            #expect(!credit.licenseName.isEmpty, "\(credit.name) has no license name")
            #expect(!credit.version.isEmpty, "\(credit.name) has no version")
            #expect(credit.homepageURL != nil, "\(credit.name) has no homepage")
        }
    }

    @Test("identifies by name")
    func identifiesByName() {
        #expect(SoftwareCredit.fixture(name: "ZIPFoundation", kind: .library).id == "ZIPFoundation")
    }

    // A credit naming an absent resource is deliberately not covered: the
    // missing-license path trips an `assertionFailure`, which traps the test
    // process rather than raising a catchable issue in a debug build.
}
