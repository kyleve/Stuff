import PeriscopeCore

@LogScope("AppIconCatalog")
enum AppIconCatalogLog {
    @LogEvent("manifest-unreadable", level: .fault)
    struct ManifestUnreadable {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to load the bundled app-icon manifest: \(description)"
        }
    }
}
