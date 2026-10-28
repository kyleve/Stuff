import Foundation

/// Domain-level mirror of `CLAuthorizationStatus`, kept free of CoreLocation so
/// it can cross actor boundaries (`Sendable`) and be rendered by the UI layer
/// without importing CoreLocation.
public enum LocationAuthorizationStatus: Sendable, Hashable {
    /// The user hasn't been asked yet.
    case notDetermined
    /// Denied by a device-level restriction (e.g. parental controls).
    case restricted
    /// The user explicitly declined.
    case denied
    /// Granted only while the app is in use — not enough for the background,
    /// cross-launch tracking this app relies on.
    case whenInUse
    /// Granted always, including background — the only status that supports
    /// passive background tracking.
    case always

    /// Whether this status permits the background significant-change / visit
    /// monitoring the app uses to log presence across launches.
    public var allowsBackgroundTracking: Bool {
        self == .always
    }

    /// Whether a one-shot foreground fix (`requestCurrentLocation()`) can
    /// succeed: any granted status, including When-In-Use. Broader than
    /// `allowsBackgroundTracking` because a foreground fix doesn't need Always.
    public var allowsForegroundFix: Bool {
        self == .whenInUse || self == .always
    }

    /// Whether the user has actively refused (vs. simply not been asked), so
    /// the UI can route to the Settings app instead of re-prompting.
    public var isDenied: Bool {
        self == .denied || self == .restricted
    }
}
