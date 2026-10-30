import PeriscopeCore

@LogScope("WhereTheme")
enum WhereThemeLog {
    @LogEvent("bundle-unreadable", level: .fault, version: 1)
    struct BundleUnreadable {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to load a bundled theme: \(error.description)"
        }
    }
}
