import PeriscopeCore

/// Structured events for the app-icon manifest load.
///
/// A bundled `AppIcons.json` that's absent or won't decode is a packaging error
/// — the `./icons` script writes it and the build embeds it, so no user action
/// produces this — hence `.fault`, paired with a debug `assertionFailure` at the
/// call site.
enum AppIconCatalogLog: LogEvent {
    /// The bundled manifest couldn't be read, so the icon picker lists nothing
    /// and the surfaces that render the selected icon fall back to Classic art.
    case manifestUnreadable(description: String)

    static let eventName = "AppIconCatalog"

    var level: LogLevel {
        .fault
    }

    var message: String {
        switch self {
            case let .manifestUnreadable(description):
                "Failed to load the bundled app-icon manifest: \(description)"
        }
    }
}
