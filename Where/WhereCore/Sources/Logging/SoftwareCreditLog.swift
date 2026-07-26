import PeriscopeCore

/// Structured events for loading a bundled third-party license text. A credit
/// naming a resource the bundle doesn't carry is a programmer error (the credit
/// and the file went out of sync), so it logs at `.fault` to match the paired
/// `assertionFailure` — and it matters: shipping a dependency without its
/// license text is a licensing problem, not a cosmetic one.
enum SoftwareCreditLog: LogEvent {
    /// The credit's license file is absent from the bundle.
    case missingLicense(credit: String, resource: String)
    /// The license file is present but could not be read as text.
    case unreadableLicense(credit: String, description: String)

    static let eventName = "SoftwareCredit"

    var level: LogLevel {
        .fault
    }

    var message: String {
        switch self {
            case let .missingLicense(credit, resource):
                "Missing bundled license text \(resource).txt for \(credit)"
            case let .unreadableLicense(credit, description):
                "Failed to read bundled license text for \(credit): \(description)"
        }
    }
}
