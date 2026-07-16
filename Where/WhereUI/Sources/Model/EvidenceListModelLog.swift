import PeriscopeCore

/// Structured events for `EvidenceListModel`. A read failure leaves the list in
/// an honest error state, so it logs at `.warning`.
enum EvidenceListModelLog: LogEvent {
    case loadFailed(year: Int, description: String)

    static let eventName = "EvidenceListModel"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .loadFailed(year, description):
                "Failed to load evidence for \(year): \(description)"
        }
    }

    var externalID: String? {
        switch self {
            case let .loadFailed(year, _): String(year)
        }
    }
}
