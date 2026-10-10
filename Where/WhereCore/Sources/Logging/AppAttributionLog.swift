import PeriscopeCore

/// Structured events for loading the app's bundled attribution report.
@LogScope("AppAttribution")
enum AppAttributionLog {
    @LogEvent("no-report", level: .info, message: "Bundle carries no attribution report")
    struct NoReport {}

    @LogEvent("loaded", level: .info)
    struct Loaded {
        @LogField(exposure: .shareable, kind: .count)
        var creditCount: Int

        var message: String {
            "Loaded attribution report with \(creditCount) credit(s)"
        }
    }

    @LogEvent("decode-failed", level: .fault, version: 2)
    struct DecodeFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to decode bundled attribution report: \(error.description)"
        }
    }
}
