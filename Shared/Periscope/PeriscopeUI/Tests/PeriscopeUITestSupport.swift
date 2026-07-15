import PeriscopeCore

/// Shared fixture events for the UI suites.
struct AppLogs: LogEvent {
    var message: String {
        "app"
    }
}

struct PhotoLogs: LogEvent {
    var photoID: String
    var message: String {
        "photo \(photoID)"
    }
}

/// A sinkless system — assertions read the synchronous recent buffer.
func makeSystem() -> Periscope {
    Periscope(configuration: Periscope.Configuration(), sinks: [])
}
