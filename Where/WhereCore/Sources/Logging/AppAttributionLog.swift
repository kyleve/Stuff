import PeriscopeCore

/// Structured events for loading the app's bundled attribution report.
@LogScope("AppAttribution")
enum AppAttributionLog {
    @LogEvent("no-report", level: .info, message: "Bundle carries no attribution report")
    struct NoReport {}

    @LogEvent("loaded", level: .info)
    struct Loaded {
        @LogField("credit_count", exposure: .shareable, kind: .count)
        var creditCount: Int

        var message: String {
            "Loaded attribution report with \(creditCount) credit(s)"
        }
    }

    @LogEvent("decode-failed", level: .fault)
    struct DecodeFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to decode bundled attribution report: \(description)"
        }
    }
}
