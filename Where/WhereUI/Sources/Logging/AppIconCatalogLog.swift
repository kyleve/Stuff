import PeriscopeCore

@LogScope("AppIconCatalog")
enum AppIconCatalogLog {
    @LogEvent("manifest-unreadable", level: .fault, version: 2)
    struct ManifestUnreadable {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to load the bundled app-icon manifest: \(error.description)"
        }
    }
}
