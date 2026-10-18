import PeriscopeCore

@LogScope("InstallerKit")
enum UpdateLog {
    enum SpanName: Hashable {
        case fetch
    }

    @LogEvent("check-failed", level: .warning, version: 1)
    struct CheckFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Update check failed: \(error.description)"
        }
    }

    @LogEvent("cache-rejected", level: .warning, version: 1)
    struct CacheRejected {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Discarded invalid update cache: \(error.description)"
        }
    }
}
