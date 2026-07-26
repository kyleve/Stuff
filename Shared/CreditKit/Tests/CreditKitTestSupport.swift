@_spi(Testing) import CreditKit
import Foundation

extension SoftwareCredit {
    /// A credit pointing at a real vendored notice by default, so
    /// ``SoftwareCredit/licenseText()`` resolves without tripping the
    /// missing-resource `assertionFailure`.
    static func fixture(
        name: String,
        kind: Kind,
        resource: String = "ZIPFoundation",
    ) -> SoftwareCredit {
        SoftwareCredit(
            name: name,
            kind: kind,
            version: "1.2.3",
            homepageURL: URL(string: "https://example.com"),
            licenseName: "MIT License",
            licenseResource: resource,
        )
    }
}
