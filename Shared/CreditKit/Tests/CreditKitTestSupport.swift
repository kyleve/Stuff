import CreditKit
import Foundation

extension SoftwareCredit {
    static func fixture(
        name: String = "Example",
        kind: Kind = .library,
        version: String = "1.2.3",
        licenseName: String = "MIT License",
        licenseText: String = "Copyright (c) 2026 Example Author",
    ) -> SoftwareCredit {
        SoftwareCredit(
            name: name,
            kind: kind,
            version: version,
            homepageURL: URL(string: "https://example.com/\(name)"),
            license: LicenseNotice(name: licenseName, text: licenseText),
        )
    }
}

enum SampleReport {
    /// The JSON shape `generate-attribution.rb` writes. Kept as a literal rather
    /// than round-tripped from an encoder so a change to the Swift types that
    /// silently breaks the wire format fails a test.
    static let json = """
    {
      "credits": [
        {
          "name": "Linked",
          "kind": "library",
          "version": "0.9.20",
          "homepageURL": "https://github.com/example/linked",
          "license": { "name": "MIT License", "text": "Linked notice." }
        },
        {
          "name": "Tool",
          "kind": "developmentTool",
          "version": "e710f8d577cc",
          "homepageURL": "https://github.com/example/tool",
          "license": { "name": "Apache License 2.0", "text": "Tool notice." }
        }
      ]
    }
    """
}
