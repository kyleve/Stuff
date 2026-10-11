import PeriscopeCore

/// Structured events for an unreadable widget presentation file.
@LogScope("WidgetPresentationStore")
enum WidgetPresentationStoreLog {
    @LogEvent("unreadable-presentation", level: .warning, version: 2)
    struct UnreadablePresentation {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Discarded unreadable widget presentation: \(error.description)"
        }
    }
}
