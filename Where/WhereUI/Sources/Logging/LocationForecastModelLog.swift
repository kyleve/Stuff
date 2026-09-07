import PeriscopeCore

enum LocationForecastModelLog: LogEvent {
    case loadFailed(description: String)
    case saveFailed(description: String)
    case clearFailed(description: String)

    static let eventName = "LocationForecast"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .loadFailed(description):
                "Failed to load the planned stay: \(description)"
            case let .saveFailed(description):
                "Failed to save the planned stay: \(description)"
            case let .clearFailed(description):
                "Failed to clear the planned stay: \(description)"
        }
    }
}
