import PeriscopeCore

/// Structured events for an unreadable widget presentation file.
@LogScope("WidgetPresentationStore")
enum WidgetPresentationStoreLog {
    @LogEvent("unreadable-presentation", level: .warning)
    struct UnreadablePresentation {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Discarded unreadable widget presentation: \(description)"
        }
    }
}
