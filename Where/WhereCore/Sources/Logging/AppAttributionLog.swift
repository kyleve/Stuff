import PeriscopeCore

/// Structured events for loading the app's bundled attribution report.
///
/// The two failure cases are deliberately not the same severity. A bundle
/// without a report is a *legitimate* state — only the app target ships one, so
/// the RegionViewer, `StuffTestHost`, and the extensions have none — and says so
/// at `.info`. A report that is present but won't decode is a corrupt bundled
/// resource, so it logs at `.fault` to match the paired `assertionFailure`, and
/// it matters beyond a blank screen: the report is how the app discharges its
/// attribution obligations.
enum AppAttributionLog: LogEvent {
    /// The bundle carries no report. Expected outside the app target.
    case noReport
    /// The report decoded successfully into `creditCount` entries.
    case loaded(creditCount: Int)
    /// The report was present but could not be decoded.
    case decodeFailed(description: String)

    static let eventName = "AppAttribution"

    var level: LogLevel {
        switch self {
            case .decodeFailed: .fault
            case .noReport, .loaded: .info
        }
    }

    var message: String {
        switch self {
            case .noReport:
                "Bundle carries no attribution report"
            case let .loaded(creditCount):
                "Loaded attribution report with \(creditCount) credit(s)"
            case let .decodeFailed(description):
                "Failed to decode bundled attribution report: \(description)"
        }
    }

    var remoteFields: [RemoteLogField] {
        switch self {
            case let .loaded(creditCount):
                [RemoteLogField(
                    key: RemoteLogFieldKey("credit_count"),
                    value: .count(creditCount),
                )]
            case .noReport, .decodeFailed:
                []
        }
    }
}
