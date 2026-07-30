import PeriscopeCore

/// Structured events for `LocationNamer`'s reverse geocoding.
///
/// Place names are best-effort sugar over coordinates the app already stores —
/// nothing depends on one resolving — so a failure is degraded-but-handled and
/// logs at `.warning`. Deliberately *not* logged: a lookup that simply has no
/// match (mid-ocean, an unnamed place). That's a legitimate empty answer, and
/// warning on it would bury the real failures under the common case.
///
/// No coordinate rides on these events: the reason a geocode failed doesn't
/// depend on where it was, and the app's diagnostics store shouldn't accumulate
/// the user's positions as a side effect of a network error.
enum LocationNamerLog: LogEvent {
    /// The geocoder refused the coordinate outright, so no request could be
    /// made (an out-of-range or non-finite value reached the namer).
    case unusableCoordinate
    /// The geocode request failed — offline, rate-limited, or a service error.
    case geocodeFailed(description: String)

    static let eventName = "LocationNamer"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case .unusableCoordinate:
                "Skipped a place-name lookup for an unusable coordinate"
            case let .geocodeFailed(description):
                "Reverse geocoding failed: \(description)"
        }
    }
}
