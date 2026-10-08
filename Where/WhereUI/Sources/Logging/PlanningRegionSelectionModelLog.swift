import PeriscopeCore

enum PlanningRegionSelectionModelLog: LogEvent {
    case loadFailed(description: String)

    static let eventName = "PlanningRegions"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .loadFailed(description):
                "Failed to load tracked regions for planning: \(description)"
        }
    }
}
