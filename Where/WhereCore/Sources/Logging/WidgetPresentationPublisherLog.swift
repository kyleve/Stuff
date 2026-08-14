import PeriscopeCore

/// Structured events for publishing the widget presentation theme.
@LogScope("WidgetPresentationPublisher")
enum WidgetPresentationPublisherLog {
    @LogEvent("published")
    struct Published {
        @LogField("theme", exposure: .restricted, kind: .technicalState)
        var theme: String
        var message: String {
            "Published widget presentation theme \(theme)"
        }
    }

    @LogEvent("publish-failed", level: .error)
    struct PublishFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to publish widget presentation: \(description)"
        }
    }
}
