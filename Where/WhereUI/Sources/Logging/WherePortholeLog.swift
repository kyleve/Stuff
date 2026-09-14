import PeriscopeCore
import WhereCore

/// Failure stages are public log metadata. Captured values and credentials never enter the event.
enum WherePortholeLog: LogEvent {
    enum Stage: String,
        Codable { case activation, capture, presentation, agent, screenshot, github }
    case failed(Stage)

    static let logger = WhereLog.root(WherePortholeLog.self)
    static let eventName = "Porthole"
    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .failed(stage): "Porthole \(stage.rawValue) failed; the debugger contains error details"
        }
    }
}
