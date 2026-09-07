import PeriscopeCore

/// Process-level events from the Where application host.
enum WhereAppLog: LogEvent {
    case diagnosticProviderStartupFailed

    var level: LogLevel {
        .error
    }

    var message: String {
        switch self {
            case .diagnosticProviderStartupFailed:
                "The diagnostic reporting provider did not start."
        }
    }
}
