import PeriscopeCore

/// Shared fixture events for the UI suites.
@LogScope("AppLogs")
enum AppLogs {
    @LogEvent("event", message: "app")
    struct Event {}
}

@LogScope("PhotoLogs")
enum PhotoLogs {
    @LogEvent("event")
    struct Event {
        @LogField("photo_id", exposure: .restricted, kind: .identifier)
        var photoID: String
        var message: String {
            "photo \(photoID)"
        }
    }
}

/// A sinkless system — assertions read the synchronous recent buffer.
func makeSystem() -> Periscope {
    Periscope(configuration: Periscope.Configuration(), sinks: [])
}
